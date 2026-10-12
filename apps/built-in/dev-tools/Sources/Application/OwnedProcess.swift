// @frontmatter:start
// Spawns and reaps bounded-output child process groups with timeout and cleanup handling.
// @frontmatter:end
import Darwin
import Foundation

/// Owns a process group until final signalling is complete. Never signals a reaped PID.
/// Native code that deliberately escapes its process group is outside this boundary.
final class OwnedProcess: @unchecked Sendable {
	enum Failure: Error, Equatable {
		case launch, outputExceeded, timedOut, cleanupFailed, reapFailed
	}
	private let lock = NSLock()
	private var pid: pid_t
	private var outputFD: Int32
	private var bytes = Data()
	private let limit: Int
	private let gracefulSignal: Int32
	private let gracePeriod: Duration
	private var overflow = false
	private var finished = false
	private var cleanupError: Failure?
	private var exitStatus: Int32?

	init(
		executable: URL, arguments: [String], directory: URL,
		environment: [String: String], outputLimit: Int,
		gracefulSignal: Int32 = SIGTERM, gracePeriod: Duration = .milliseconds(100)
	) throws {
		limit = outputLimit
		self.gracefulSignal = gracefulSignal
		self.gracePeriod = gracePeriod
		var fds: [Int32] = [0, 0]
		guard
			pipe(&fds) == 0
		else { throw Failure.launch }
		var keepReader = false
		defer {
			close(fds[1])
			if !keepReader { close(fds[0]) }
		}
		guard
			fcntl(fds[0], F_SETFL, O_NONBLOCK) == 0,
			fcntl(fds[0], F_SETFD, FD_CLOEXEC) == 0
		else { throw Failure.launch }
		var actions: posix_spawn_file_actions_t?
		var attributes: posix_spawnattr_t?
		guard
			posix_spawn_file_actions_init(&actions) == 0
		else { throw Failure.launch }
		defer { posix_spawn_file_actions_destroy(&actions) }
		guard
			posix_spawnattr_init(&attributes) == 0
		else { throw Failure.launch }
		defer { posix_spawnattr_destroy(&attributes) }
		var mask = sigset_t()
		sigemptyset(&mask)
		var defaults = sigset_t()
		sigemptyset(&defaults)
		for signal in [SIGTERM, SIGINT, SIGHUP, SIGPIPE, SIGCHLD] { sigaddset(&defaults, signal) }
		guard
			posix_spawnattr_setsigmask(&attributes, &mask) == 0,
			posix_spawnattr_setsigdefault(&attributes, &defaults) == 0,
			posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
			posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO) == 0,
			posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO) == 0,
			posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0,
			posix_spawnattr_setflags(
				&attributes,
				Int16(
					POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK
						| POSIX_SPAWN_SETSIGDEF)) == 0,
			posix_spawnattr_setpgroup(&attributes, 0) == 0
		else { throw Failure.launch }
		let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
		let envp =
			environment.sorted(by: { $0.key < $1.key }).map { strdup("\($0.key)=\($0.value)") } + [nil]
		defer {
			for pointer in argv { free(pointer) }
			for pointer in envp { free(pointer) }
		}
		var child: pid_t = 0
		let result = argv.withUnsafeBufferPointer { args in
			envp.withUnsafeBufferPointer { env in
				posix_spawn(
					&child, executable.path, &actions, &attributes,
					UnsafeMutablePointer(mutating: args.baseAddress!),
					UnsafeMutablePointer(mutating: env.baseAddress!))
			}
		}
		guard
			result == 0
		else { throw Failure.launch }
		pid = child
		outputFD = fds[0]
		keepReader = true
	}

	var processID: Int32 { pid }
	var output: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }

	private func drainLocked() {
		guard
			outputFD >= 0
		else { return }
		var buffer = [UInt8](repeating: 0, count: 4096)
		// A producer cannot monopolize the polling/cleanup thread.
		for _ in 0..<32 {
			let count = read(outputFD, &buffer, buffer.count)
			if count > 0 {
				let remaining = max(0, limit - bytes.count)
				bytes.append(contentsOf: buffer.prefix(min(count, remaining)))
				if count > remaining { overflow = true }
			} else {
				break
			}
		}
	}

	private func poll() throws -> Int32? {
		try lock.withLock {
			if finished {
				if let cleanupError { throw cleanupError }
				return exitStatus
			}
			drainLocked()
			if overflow { throw Failure.outputExceeded }
			var info = siginfo_t()
			guard
				waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0
			else { throw Failure.cleanupFailed }
			guard
				info.si_pid == pid
			else { return nil }
			return info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status
		}
	}

	func isAlive() throws -> Bool { try poll() == nil }

	func wait(timeout: Duration) async throws -> Int32 {
		let deadline = ContinuousClock.now.advanced(by: timeout)
		do {
			while true {
				try Task.checkCancellation()
				if let status = try poll() {
					try await stop()
					try Task.checkCancellation()
					return status
				}
				guard
					ContinuousClock.now < deadline
				else { throw Failure.timedOut }
				try await Task.sleep(for: .milliseconds(10))
			}
		} catch {
			try await stop()
			throw error
		}
	}

	func stop() async throws {
		// Detached cleanup must finish even when the operation's task is cancelled.
		try await Task.detached { try self.cleanup() }.value
	}

	/// Freeze each parent before enumerating its children. A stopped parent cannot reap
	/// those children, so their PIDs remain reserved until our leaf-first final signals.
	/// This also covers SwiftPM workers that create separate process groups.
	private func terminateDescendantsLocked() throws -> [pid_t] {
		let deadline = ContinuousClock.now.advanced(by: .seconds(2))
		func stopped(_ target: pid_t) throws -> Bool {
			guard
				kill(target, SIGSTOP) == 0
			else { throw Failure.cleanupFailed }
			while ContinuousClock.now < deadline {
				var info = proc_bsdinfo()
				guard
					proc_pidinfo(
						target, PROC_PIDTBSDINFO, 0, &info,
						Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size
				else { throw Failure.cleanupFailed }
				if info.pbi_status == SZOMB { return false }
				if info.pbi_status == SSTOP { return true }
				usleep(1_000)
			}
			throw Failure.cleanupFailed
		}
		var frozen: [pid_t] = []
		do {
			guard
				try stopped(pid)
			else { return [] }
			var parents = [pid]
			while let parent = parents.popLast() {
				var children = [pid_t](repeating: 0, count: 2048)
				let capacity = Int32(children.count * MemoryLayout<pid_t>.size)
				let count = proc_listchildpids(parent, &children, capacity)
				guard
					count >= 0,
					count < children.count
				else { throw Failure.cleanupFailed }
				for child in children.prefix(Int(count)) where child > 0 {
					guard
						frozen.count < 2048
					else { throw Failure.cleanupFailed }
					// The parent is frozen and alive: it cannot reap/reuse this child's PID.
					frozen.append(child)
					if try stopped(child) { parents.append(child) }
				}
			}
			for child in frozen.reversed() { kill(child, SIGKILL) }
			kill(pid, SIGCONT)
			return frozen
		} catch {
			for child in frozen.reversed() { kill(child, SIGKILL) }
			kill(pid, SIGCONT)
			throw error
		}
	}

	private func cleanup() throws {
		try lock.withLock {
			if finished {
				if let cleanupError { throw cleanupError }
				return
			}
			defer {
				finished = true
				close(outputFD)
				outputFD = -1
			}
			var descendants: [pid_t] = []
			var treeCleanupFailed = false
			var observed = siginfo_t()
			if waitid(P_PID, id_t(pid), &observed, WEXITED | WNOHANG | WNOWAIT) == 0,
				observed.si_pid == 0
			{
				do { descendants = try terminateDescendantsLocked() } catch { treeCleanupFailed = true }
			}
			// The unreaped leader reserves the group identifier through BOTH signals.
			kill(-pid, gracefulSignal)
			let grace = ContinuousClock.now.advanced(by: gracePeriod)
			while ContinuousClock.now < grace {
				drainLocked()
				usleep(5_000)
			}
			kill(-pid, SIGKILL)
			var status: Int32 = 0
			let deadline = ContinuousClock.now.advanced(by: .seconds(2))
			var reaped = false
			while ContinuousClock.now < deadline {
				drainLocked()
				let value = waitpid(pid, &status, WNOHANG)
				if value == pid {
					reaped = true
					break
				}
				if value < 0 && errno != EINTR { break }
				usleep(5_000)
			}
			// No more signals are permitted after waitpid releases the PID.
			guard
				reaped
			else {
				cleanupError = .reapFailed
				throw Failure.reapFailed
			}
			exitStatus = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
			var groupGone = false
			while ContinuousClock.now < deadline {
				let value = kill(-pid, 0)
				let code = errno
				if value == -1 && code == ESRCH {
					groupGone = true
					break
				}
				usleep(5_000)
			}
			guard
				groupGone,
				!treeCleanupFailed
			else {
				cleanupError = .cleanupFailed
				throw Failure.cleanupFailed
			}
			for child in descendants {
				while kill(child, 0) == 0 && ContinuousClock.now < deadline { usleep(5_000) }
				guard
					kill(child, 0) == -1
				else {
					cleanupError = .cleanupFailed
					throw Failure.cleanupFailed
				}
			}
			drainLocked()
		}
	}
}
