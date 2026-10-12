// @frontmatter:start
// Rewrites Swift guard layout using parsed syntax while preserving complex condition contents.
// @frontmatter:end
import Foundation
import SwiftParser
import SwiftSyntax

private struct Replacement {
	let range: Range<Int>
	let text: String
}

public func formatGuards(_ source: String) -> String {
	guard !source.contains("\r") else { return source }
	let tree = Parser.parse(source: source)
	guard !tree.hasError else { return source }
	let collector = GuardCollector(source: source)
	collector.walk(tree)
	var bytes = Array(source.utf8)
	for edit in collector.edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
		bytes.replaceSubrange(edit.range, with: edit.text.utf8)
	}
	return String(decoding: bytes, as: UTF8.self)
}

private final class GuardCollector: SyntaxVisitor {
	let source: [UInt8]
	var edits: [Replacement] = []

	init(source: String) {
		self.source = Array(source.utf8)
		super.init(viewMode: .sourceAccurate)
	}

	override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
		let start = node.guardKeyword.positionAfterSkippingLeadingTrivia.utf8Offset
		let lineStart = source[..<start].lastIndex(of: 10).map { $0 + 1 } ?? 0
		let prefix = String(decoding: source[lineStart..<start], as: UTF8.self)
		guard prefix.allSatisfy({ $0 == "\t" || $0 == " " }),
			let first = node.conditions.first, let last = node.conditions.last
		else { return .visitChildren }
		let conditionIndent = prefix + "\t"
		replaceGap(
			node.guardKeyword.endPositionBeforeTrailingTrivia.utf8Offset,
			first.condition.positionAfterSkippingLeadingTrivia.utf8Offset, indent: conditionIndent)
		for (current, next) in zip(node.conditions, node.conditions.dropFirst()) {
			guard let comma = current.trailingComma else { continue }
			replaceGap(
				comma.endPositionBeforeTrailingTrivia.utf8Offset,
				next.condition.positionAfterSkippingLeadingTrivia.utf8Offset, indent: conditionIndent)
		}
		replaceGap(
			last.condition.endPositionBeforeTrailingTrivia.utf8Offset,
			node.elseKeyword.positionAfterSkippingLeadingTrivia.utf8Offset,
			indent: prefix, commentIndent: conditionIndent)
		formatBody(node.body, indentation: prefix)
		return .visitChildren
	}

	private func replaceGap(
		_ start: Int, _ end: Int, indent: String,
		commentIndent: String? = nil
	) {
		guard start <= end else { return }
		let original = String(decoding: source[start..<end], as: UTF8.self)
		let comments = original.split(separator: "\n").map {
			$0.trimmingCharacters(in: .whitespacesAndNewlines)
		}.filter { !$0.isEmpty }
		let replacement =
			comments.isEmpty
			? "\n" + indent
			: "\n" + comments.map { (commentIndent ?? indent) + $0 }.joined(separator: "\n")
				+ "\n" + indent
		if original != replacement { edits.append(Replacement(range: start..<end, text: replacement)) }
	}

	private func formatBody(_ body: CodeBlockSyntax, indentation: String) {
		let start = body.leftBrace.endPositionBeforeTrailingTrivia.utf8Offset
		let end = body.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
		guard start <= end else { return }
		let original = String(decoding: source[start..<end], as: UTF8.self)
		guard !original.contains("//"), !original.contains("/*"), !original.contains("guard ") else {
			return
		}
		let statements = body.statements.map {
			$0.description.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard !statements.isEmpty, statements.allSatisfy({ !$0.contains("\n") }) else { return }
		let contents = statements.map { $0.hasSuffix(";") ? String($0.dropLast()) : $0 }
		let replacement: String
		if contents.count == 1,
			indentation.utf8.count + "else { ".utf8.count + contents[0].utf8.count + " }".utf8.count
				<= 100
		{
			replacement = " " + contents[0] + " "
		} else {
			replacement =
				"\n" + contents.map { indentation + "\t" + $0 }.joined(separator: "\n")
				+ "\n" + indentation
		}
		if replacement != original { edits.append(Replacement(range: start..<end, text: replacement)) }
	}
}
