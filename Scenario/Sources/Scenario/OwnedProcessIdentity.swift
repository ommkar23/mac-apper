// @frontmatter:start
// Captures immutable kernel process identities and confirms exact-owned TERM/KILL reaping before scenario files are removed.
// @frontmatter:end
import Darwin
import Foundation

public struct OwnedProcessIdentity {
	public let pid: Int32
	public let start: UInt64
	public let path: String
	public init(pid: Int32, start: UInt64, path: String) {
		self.pid = pid; self.start = start; self.path = path
	}
	public static func capture(_ pid: Int32) throws -> Self {
		guard
			pid > 1,
			let path = kernelPath(pid),
			let start = kernelStart(pid)
		else { throw ScenarioFailure.message("owned process identity unavailable") }
		let identity = Self(pid: pid, start: start, path: path)
		try identity.validate()
		return identity
	}
	private func validate() throws {
		guard
			pid > 1,
			Self.kernelPath(pid) == path,
			Self.kernelStart(pid) == start
		else { throw ScenarioFailure.message("owned process identity mismatch; retain fixtures") }
	}
	public func requireReaped() throws {
		guard
			pid > 1,
			kill(pid, 0) != 0,
			errno == ESRCH
		else { throw ScenarioFailure.message("owned process not reaped; retain fixtures") }
	}
	// Internal seam: deterministic races use the same teardown state machine, without real signals.
	struct Operations {
		let path: (Int32) -> String?
		let start: (Int32) -> UInt64?
		// nil means success; otherwise the errno captured immediately after kill.
		let signal: (Int32, Int32) -> Int32?
		let wait: (TimeInterval) -> Void
	}
	public func reap() throws {
		try reap(
			using: Operations(
				path: Self.kernelPath, start: Self.kernelStart,
				signal: { pid, signal in kill(pid, signal) == 0 ? nil : errno },
				wait: { wait(seconds: $0) }))
	}
	func reap(using operations: Operations) throws {
		guard
			pid > 1
		else { throw ScenarioFailure.message("invalid owned PID; retain fixtures") }
		func requireReaped() throws {
			guard
				operations.signal(pid, 0) == ESRCH
			else { throw ScenarioFailure.message("owned process not reaped; retain fixtures") }
		}
		func signalIfOwned(_ signal: Int32) throws -> Bool {
			guard
				operations.path(pid) == path,
				operations.start(pid) == start
			else {
				// A failed lookup can be an exit race, not proof of either exit or ownership.
				guard
					operations.signal(pid, 0) == ESRCH
				else { throw ScenarioFailure.message("owned process identity mismatch; retain fixtures") }
				return false
			}
			guard
				operations.signal(pid, signal) == nil
			else {
				// Even signal-time ESRCH needs a fresh probe: the PID may already be reused.
				try requireReaped()
				return false
			}
			return true
		}
		if operations.signal(pid, 0) != nil { try requireReaped(); return }
		guard
			try signalIfOwned(SIGTERM)
		else { return }
		operations.wait(2)
		if operations.signal(pid, 0) == nil {
			guard
				try signalIfOwned(SIGKILL)
			else { return }
		}
		operations.wait(10)
		try requireReaped()
	}
	private func wait(seconds: TimeInterval) {
		let deadline = Date().addingTimeInterval(seconds)
		while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
	}
	private static func kernelPath(_ pid: Int32) -> String? {
		var buffer = [UInt8](repeating: 0, count: 4096)
		let count = buffer.withUnsafeMutableBufferPointer { proc_pidpath(pid, $0.baseAddress, 4096) }
		guard
			count > 0,
			count <= 4096
		else { return nil }
		return String(decoding: buffer.prefix(Int(count)).prefix { $0 != 0 }, as: UTF8.self)
	}
	private static func kernelStart(_ pid: Int32) -> UInt64? {
		var info = proc_bsdinfo()
		let size = Int32(MemoryLayout<proc_bsdinfo>.size)
		guard
			proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
		else { return nil }
		return info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec
	}
}
