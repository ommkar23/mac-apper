// @frontmatter:start
// Formats byte-bounded Preview diagnostics and identifies subprocess phases without exposing captured payloads.
// @frontmatter:end
import Foundation

struct PreviewProcessDiagnostic: Error, Sendable {
	enum Phase: String, Sendable {
		case appViewsBuild, binPath, sdkDiscovery, previewAST, productionAST
		case snapshotBuild, snapshotExecution
	}
	let summary: String

	init(phase: Phase, error: any Error, outputLimit: Int) {
		let code: String
		switch error {
		case let failure as OwnedProcess.Failure: code = String(describing: failure)
		case is SwiftToolchain.Failure: code = "toolchainUnavailable"
		case PreviewRendering.Failure.processFailed: code = "processFailed"
		default: code = "processError"
		}
		// OwnedProcess keeps a bounded prefix, not a final stream tail. Cleanup can drain
		// additional bytes after a non-overflow failure; its final overflow flag is private.
		let truncated = (error as? OwnedProcess.Failure) == .outputExceeded ? "true" : "unknown"
		// Omit ALL compiler/worker output, including build errors: arbitrary generated
		// source, paths and secrets cannot be safely redacted with token heuristics.
		summary =
			"\(code): phase=\(phase.rawValue); outputLimitBytes=\(outputLimit); "
			+ "outputTruncated=\(truncated); capture=boundedPrefix; output=omitted (privacy policy)."
	}
}

enum PreviewDiagnostic {
	static func bounded(_ message: String) -> String {
		let marker = " [summary truncated]"
		let limit = 4096
		var result = ""
		var count = 0
		for scalar in message.unicodeScalars {
			// Preserve trusted repair-example line breaks; normalize other controls.
			let unsafe =
				scalar != "\n"
				&& (CharacterSet.controlCharacters.contains(scalar)
					|| CharacterSet.newlines.contains(scalar))
			let safe = unsafe ? " " : String(scalar)
			guard
				count + safe.utf8.count <= limit - marker.utf8.count
			else { return result + marker }
			result += safe
			count += safe.utf8.count
		}
		return result
	}

	static func summary(_ error: any Error, sourcePath: String) -> String {
		if let process = error as? PreviewProcessDiagnostic { return bounded(process.summary) }
		if let discovery = error as? PreviewDiscovery.Failure {
			let safePath = sourcePath.replacingOccurrences(of: "\n", with: " ")
			return bounded(discovery.diagnostic(sourcePath: bounded(safePath)))
		}
		// Never stringify arbitrary errors: Foundation/toolchain errors can embed paths.
		if let rendering = error as? PreviewRendering.Failure {
			switch rendering {
			case .processFailed: return "processFailed: output=omitted (privacy policy)."
			default: return bounded(String(describing: rendering))
			}
		}
		return "previewFailed: diagnostic details omitted (privacy policy)."
	}
}
