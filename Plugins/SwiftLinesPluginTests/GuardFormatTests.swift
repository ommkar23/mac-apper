// @frontmatter:start
// Tests guard-style formatting, comment preservation, and idempotence.
// @frontmatter:end
import GuardFormatCore
import Testing

@Test func guardConditionsAndSingleStatementAreLaidOut() {
	let input = """
		func example(_ value: Int?, _ other: Int?) {
			guard let value, let other = other, value > 0 else {
				return
			}
		}
		"""
	let expected = """
		func example(_ value: Int?, _ other: Int?) {
			guard
				let value,
				let other = other,
				value > 0
			else { return }
		}
		"""
	#expect(formatGuards(input) == expected)
	#expect(formatGuards(expected) == expected)
}

@Test func multiStatementElseBodyRemainsMultiline() {
	let input = """
		func example(_ value: Int?) {
			guard let value else { print("missing"); return }
		}
		"""
	let expected = """
		func example(_ value: Int?) {
			guard
				let value
			else {
				print("missing")
				return
			}
		}
		"""
	#expect(formatGuards(input) == expected)
}

@Test func longSingleStatementRemainsInAMultilineBody() {
	let input = """
		func example(_ value: Int?) {
			guard let value else {
				throw Failure.message("a deliberately lengthy explanation of why this value cannot be used here")
			}
		}
		"""
	let formatted = formatGuards(input)
	#expect(formatted.contains("else {\n"))
	#expect(formatted.contains("\t\tthrow Failure.message"))
}

@Test func commentedGuardsStillPutConditionsOnTheirOwnLines() {
	let input = """
		func example(_ value: Int?) {
			let text = "guard let fake else { return }"
			guard let value /* keep comment */ else { return }
		}
		"""
	let result = formatGuards(input)
	#expect(result.contains("\tguard\n\t\tlet value\n\t\t/* keep comment */\n\telse { return }"))
	#expect(result.contains("let text = \"guard let fake else { return }\""))
	#expect(formatGuards(result) == result)
}

@Test func multilineConditionStartsOnItsOwnLine() {
	let input = """
		func example(_ value: Int?) {
			guard let value = value.map(
				{ $0 + 1 }), value > 0 else { return }
		}
		"""
	let result = formatGuards(input)
	#expect(result.contains("\tguard\n\t\tlet value = value.map("))
	#expect(result.contains("\n\t\tvalue > 0\n\telse { return }"))
}
