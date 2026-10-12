import Darwin
@testable import Scenario
import Testing

private final class ExitRace {
	let identity = OwnedProcessIdentity(pid: 42, start: 123, path: "/owned/child")
	var exited = false
	var inspections = 0
	var signals: [Int32] = []
	var onPath: (() -> String?)?
	var onStart: (() -> UInt64?)?
	var onSignal: ((Int32) -> Int32?)?
	var onWait: (() -> Void)?
	var probeError: Int32?

	func reap() throws {
		try identity.reap(
			using: .init(
				path: { _ in
					self.inspections += 1
					if let onPath = self.onPath { return onPath() }
					return self.exited ? nil : self.identity.path
				},
				start: { _ in
					if let onStart = self.onStart { return onStart() }
					return self.exited ? nil : self.identity.start
				},
				signal: { _, signal in
					if signal == 0 { return self.exited ? ESRCH : self.probeError }
					self.signals.append(signal)
					if let onSignal = self.onSignal { return onSignal(signal) }
					self.exited = true
					return nil
				}, wait: { _ in self.onWait?() }))
	}
}

@Test(arguments: [
	"already", "path", "start", "mismatch-exit", "term", "before-escalation", "escalation-path",
	"escalation-start", "kill", "kill-success",
])
func ownedExitRacesRequireFreshESRCH(stage: String) throws {
	let race = ExitRace()
	if stage == "already" { race.exited = true }
	if stage == "path" || stage == "escalation-path" {
		race.onPath = {
			if stage == "path" || race.inspections == 2 { race.exited = true }
			return race.exited ? nil : race.identity.path
		}
	}
	if stage == "start" || stage == "escalation-start" {
		race.onStart = {
			if stage == "start" || race.inspections == 2 { race.exited = true }
			return race.exited ? nil : race.identity.start
		}
	}
	if stage == "before-escalation" { race.onWait = { race.exited = true } }
	if stage.contains("escalation") || stage == "kill" {
		race.onSignal = { signal in
			if signal == SIGTERM { return nil }
			race.exited = true
			return ESRCH
		}
	}
	if stage == "mismatch-exit" {
		race.onStart = {
			race.exited = true; return 124
		}
	}
	if stage == "term" {
		race.onSignal = { _ in
			race.exited = true; return ESRCH
		}
	}
	if stage == "kill-success" {
		race.onSignal = { signal in
			if signal == SIGKILL { race.exited = true }
			return nil
		}
	}
	try race.reap()
	#expect(race.exited)
	let expected: [Int32] =
		switch stage {
		case "already", "path", "start", "mismatch-exit": []
		case "kill", "kill-success": [SIGTERM, SIGKILL]
		default: [SIGTERM]
		}
	#expect(race.signals == expected)
}

@Test(arguments: [
	"path", "start", "unavailable", "unavailable-path", "permission", "validation-permission",
	"term-reuse", "escalation-reuse", "kill-reuse", "term-denied", "kill-denied", "not-reaped",
	"invalid-pid",
])
func ownedLiveMismatchNeverBecomesReaped(stage: String) throws {
	let race = ExitRace()
	switch stage {
	case "path": race.onPath = { "/unrelated/child" }
	case "start": race.onStart = { 124 }
	case "unavailable": race.onStart = { nil }
	case "unavailable-path": race.onPath = { nil }
	case "permission": race.probeError = EPERM
	case "validation-permission":
		race.onStart = {
			race.probeError = EPERM; return nil
		}
	case "term-reuse": race.onSignal = { _ in ESRCH }  // Fresh probe still sees a live PID.
	case "escalation-reuse":
		race.onSignal = { _ in nil }
		race.onStart = { race.inspections == 1 ? 123 : 124 }
	case "kill-reuse": race.onSignal = { $0 == SIGTERM ? nil : ESRCH }
	case "term-denied": race.onSignal = { _ in EPERM }
	case "kill-denied": race.onSignal = { $0 == SIGTERM ? nil : EPERM }
	case "not-reaped": race.onSignal = { _ in nil }
	default:
		let invalid = OwnedProcessIdentity(pid: -1, start: 123, path: "/owned/child")
		#expect(throws: (any Error).self) {
			try invalid.reap(
				using: .init(
					path: { _ in "/owned/child" }, start: { _ in 123 },
					signal: { _, _ in
						Issue.record("Invalid PID must not reach kill"); return ESRCH
					},
					wait: { _ in }))
		}
		return
	}
	#expect(throws: (any Error).self) { try race.reap() }
	let expected: [Int32] =
		switch stage {
		case "term-reuse", "escalation-reuse", "term-denied": [SIGTERM]
		case "kill-reuse", "kill-denied", "not-reaped": [SIGTERM, SIGKILL]
		default: []
		}
	#expect(race.signals == expected)
	#expect(!race.exited)
}
