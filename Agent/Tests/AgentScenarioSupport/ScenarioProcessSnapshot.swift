// @frontmatter:start
// Finds a scoped Pi PID and retains multiline process arguments without logging process snapshots.
// @frontmatter:end
import Foundation

public struct ScenarioProcessSnapshot: Sendable {
	public let pid: String
	public let arguments: String
	public static func find(_ snapshot: String, sessionPath: String, expectedPID: String? = nil)
		throws -> Self
	{
		guard
			snapshot.utf8.count <= 2_000_000
		else { throw SessionAuditError.invalidMetadata }
		var records: [Self] = []
		var pid: String?
		var arguments = ""
		for line in snapshot.split(separator: "\n", omittingEmptySubsequences: false) {
			let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
			if parts.count == 2, let value = Int(parts[0]), value > 0 {
				if let pid { records.append(Self(pid: pid, arguments: arguments)) }
				pid = String(parts[0]); arguments = String(parts[1])
			} else if pid != nil {
				arguments += "\n" + line
			}
		}
		if let pid { records.append(Self(pid: pid, arguments: arguments)) }
		let matched = records.filter {
			$0.arguments.contains("--session \(sessionPath)")
				&& (expectedPID == nil || $0.pid == expectedPID)
		}
		guard
			matched.count == 1,
			let record = matched.first
		else { throw SessionAuditError.wrongScope }
		return record
	}
}
