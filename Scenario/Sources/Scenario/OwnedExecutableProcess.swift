// @frontmatter:start
// Discovers one process by an existing canonical kernel executable path and captures its immutable identity without signaling.
// @frontmatter:end
import Darwin
import Foundation

public enum OwnedExecutableProcess {
	/// Attribute a still-existing, caller-owned executable before removing its host.
	/// Absence is not exit confirmation. Ambiguous or unavailable attribution retains fixtures.
	public static func capture(executable: URL, timeout: TimeInterval = 2) throws
		-> OwnedProcessIdentity
	{
		try capture(
			executable: executable, timeout: timeout,
			using: Operations(
				inventory: inventory, path: kernelPath, capture: OwnedProcessIdentity.capture,
				now: { ProcessInfo.processInfo.systemUptime }, wait: Thread.sleep(forTimeInterval:)))
	}

	struct Inventory {
		let pids: [Int32]
		let truncated: Bool
	}

	// Discovery seams never confer signaling authority or replace identity validation.
	struct Operations {
		let inventory: () throws -> Inventory
		let path: (Int32) -> String?
		let capture: (Int32) throws -> OwnedProcessIdentity
		let now: () -> TimeInterval
		let wait: (TimeInterval) -> Void
	}

	static func capture(
		executable: URL, timeout: TimeInterval, using operations: Operations
	) throws -> OwnedProcessIdentity {
		guard
			timeout.isFinite,
			(0...60).contains(timeout)
		else { throw ScenarioFailure.message("invalid executable discovery timeout") }
		let expected = try canonicalExecutable(executable)
		let deadline = operations.now() + timeout
		repeat {
			let inventory = try operations.inventory()
			guard
				!inventory.truncated,
				inventory.pids.count < 65_536,
				Set(inventory.pids).count == inventory.pids.count
			else {
				throw ScenarioFailure.message("incomplete executable process inventory; retain fixtures")
			}
			let matches = inventory.pids.filter { $0 > 1 && operations.path($0) == expected }
			guard
				matches.count <= 1
			else {
				throw ScenarioFailure.message("ambiguous executable process ownership; retain fixtures")
			}
			if let pid = matches.first {
				let identity = try operations.capture(pid)
				guard
					identity.pid == pid,
					identity.path == expected,
					try canonicalExecutable(executable) == expected
				else { throw ScenarioFailure.message("executable capture mismatch; retain fixtures") }
				return identity
			}
			let remaining = deadline - operations.now()
			guard
				remaining > 0
			else { throw ScenarioFailure.message("owned executable process not found; retain fixtures") }
			operations.wait(min(0.05, remaining))
		} while true
	}

	private static func canonicalExecutable(_ executable: URL) throws -> String {
		guard
			executable.isFileURL,
			executable.path.hasPrefix("/"),
			!executable.path.utf8.contains(0)
		else { throw ScenarioFailure.message("invalid owned executable path") }
		// Allow system spelling aliases only beneath root-owned, non-writable ancestors.
		// Caller/project links (including a linked leaf) are never ownership evidence.
		var prefix = "", trusted = true
		let components = executable.path.split(separator: "/")
		for (index, component) in components.enumerated() {
			prefix += "/" + component
			var info = stat()
			guard
				lstat(prefix, &info) == 0
			else { throw ScenarioFailure.message("owned executable path unavailable") }
			if info.st_mode & S_IFMT == S_IFLNK {
				guard
					index < components.count - 1,
					trusted,
					info.st_uid == 0
				else { throw ScenarioFailure.message("linked owned executable path") }
				guard
					stat(prefix, &info) == 0
				else { throw ScenarioFailure.message("owned executable alias unavailable") }
			}
			trusted = trusted && info.st_uid == 0 && info.st_mode & 0o022 == 0
		}
		var info = stat()
		guard
			lstat(executable.path, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			FileManager.default.isExecutableFile(atPath: executable.path),
			let canonical = realpath(executable.path, nil)
		else { throw ScenarioFailure.message("invalid owned executable") }
		defer { free(canonical) }
		return String(cString: canonical)
	}

	private static func inventory() throws -> Inventory {
		var pids = [Int32](repeating: 0, count: 65_536)
		let count = pids.withUnsafeMutableBytes {
			proc_listallpids($0.baseAddress, Int32($0.count))
		}
		guard
			count > 0
		else { throw ScenarioFailure.message("executable process inventory unavailable") }
		return Inventory(pids: Array(pids.prefix(Int(count))), truncated: count >= pids.count)
	}

	private static func kernelPath(_ pid: Int32) -> String? {
		var bytes = [UInt8](repeating: 0, count: 4096)
		let count = bytes.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
		guard
			count > 0,
			count < bytes.count,
			let end = bytes.firstIndex(of: 0),
			end > 0
		else { return nil }
		return String(bytes: bytes.prefix(end), encoding: .utf8)
	}
}
