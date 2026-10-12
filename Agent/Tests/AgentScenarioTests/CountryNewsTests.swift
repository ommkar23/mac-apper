// @frontmatter:start
// Tests strict country-news response validation without invoking a model or Web.
// @frontmatter:end
import AgentScenarioSupport
import Foundation
import Testing

private let reference = Date(timeIntervalSince1970: 1_735_689_600)  // 2025-01-01 UTC

private func newsData(count: Int = 5, country: String = "Japan", date: String = "2024-12-31") throws
	-> Data
{
	try JSONSerialization.data(withJSONObject: [
		"country": country,
		"items": (0..<count).map { index in
			[
				"title": "Story \(index)", "publishedDate": date, "summary": "Summary \(index)",
				"sourceURL": "https://example.com/story/\(index)",
			]
		},
	])
}

@Test func countryNewsAcceptsFiveBoundedItems() throws {
	let result = try CountryNews.validate(newsData(), country: "Japan", now: reference)
	#expect(result.items.count == 5)
}

@Test(arguments: [0, 4, 6]) func countryNewsRejectsWrongItemCount(_ count: Int) throws {
	let data = try newsData(count: count)
	#expect(throws: (any Error).self) {
		try CountryNews.validate(data, country: "Japan", now: reference)
	}
}

@Test(arguments: ["2024-12-01", "2025-01-02", "2024-12-99", "yesterday"])
func countryNewsRejectsStaleFutureAndInvalidDates(_ date: String) throws {
	let data = try newsData(date: date)
	#expect(throws: (any Error).self) {
		try CountryNews.validate(data, country: "Japan", now: reference)
	}
}

@Test func countryNewsRejectsWrongCountryExtraFieldsAndDuplicateSources() throws {
	#expect(throws: (any Error).self) {
		try CountryNews.validate(newsData(country: "France"), country: "Japan", now: reference)
	}
	var record = try #require(JSONSerialization.jsonObject(with: newsData()) as? [String: Any])
	record["extra"] = true
	#expect(throws: (any Error).self) {
		try CountryNews.validate(
			JSONSerialization.data(withJSONObject: record), country: "Japan", now: reference)
	}
	record.removeValue(forKey: "extra")
	var items = try #require(record["items"] as? [[String: String]])
	items[1]["sourceURL"] = items[0]["sourceURL"]
	record["items"] = items
	#expect(throws: (any Error).self) {
		try CountryNews.validate(
			JSONSerialization.data(withJSONObject: record), country: "Japan", now: reference)
	}
}

@Test(arguments: ["title", "summary"])
func countryNewsRejectsEmptyTextAndUnknownItemFields(_ field: String) throws {
	var record = try #require(JSONSerialization.jsonObject(with: newsData()) as? [String: Any])
	var items = try #require(record["items"] as? [[String: String]])
	items[0][field] = "  "
	record["items"] = items
	#expect(throws: (any Error).self) {
		try CountryNews.validate(
			JSONSerialization.data(withJSONObject: record), country: "Japan", now: reference)
	}
	items[0][field] = "Valid"
	items[0]["extra"] = "Unexpected"
	record["items"] = items
	#expect(throws: (any Error).self) {
		try CountryNews.validate(
			JSONSerialization.data(withJSONObject: record), country: "Japan", now: reference)
	}
}

@Test(arguments: ["", "file:///etc/passwd", "https://", "https://user:password@example.com/"])
func countryNewsRejectsInvalidSources(_ source: String) throws {
	var record = try #require(JSONSerialization.jsonObject(with: newsData()) as? [String: Any])
	var items = try #require(record["items"] as? [[String: String]])
	items[0]["sourceURL"] = source
	record["items"] = items
	#expect(throws: (any Error).self) {
		try CountryNews.validate(
			JSONSerialization.data(withJSONObject: record), country: "Japan", now: reference)
	}
}
