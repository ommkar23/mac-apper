import Darwin
import Foundation
@testable import Scenario
import Testing

@Test func ownedIdentityReapsOnlyCapturedChildAndRejectsChangedIdentity() throws {
	let owned = Process()
	owned.executableURL = URL(fileURLWithPath: "/bin/sleep")
	owned.arguments = ["60"]
	try owned.run()
	let unrelated = Process()
	unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
	unrelated.arguments = ["60"]
	try unrelated.run()
	defer {
		if owned.isRunning { owned.terminate() }; owned.waitUntilExit()
		if unrelated.isRunning { unrelated.terminate() }; unrelated.waitUntilExit()
	}
	let identity = try OwnedProcessIdentity.capture(owned.processIdentifier)
	let wrong = OwnedProcessIdentity(
		pid: identity.pid, start: identity.start + 1, path: identity.path)
	#expect(throws: (any Error).self) { try wrong.reap() }
	#expect(owned.isRunning)
	try identity.reap()
	try identity.requireReaped()
	try identity.reap()  // The real child is already exited; repeated teardown is safe.
	#expect(unrelated.isRunning)
}
