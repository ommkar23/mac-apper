// @frontmatter:start
// Validates bounded five-item country-news JSON for live and offline scenario checks.
// @frontmatter:end
import Foundation

public enum CountryNewsError: Error { case invalidResponse }

public struct CountryNews: Codable, Sendable {
	public struct Item: Codable, Sendable {
		public let title: String
		public let publishedDate: String
		public let summary: String
		public let sourceURL: String
	}
	public let country: String
	public let items: [Item]

	public static func validate(_ data: Data, country: String, now: Date) throws -> Self {
		guard
			data.count <= 60_000,
			let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			Set(object.keys) == ["country", "items"],
			let entries = object["items"] as? [[String: Any]],
			entries.count == 5,
			entries.allSatisfy({ Set($0.keys) == ["title", "publishedDate", "summary", "sourceURL"] })
		else { throw CountryNewsError.invalidResponse }
		let result = try JSONDecoder().decode(Self.self, from: data)
		guard
			result.country == country,
			Set(result.items.map { $0.title.lowercased() }).count == 5,
			Set(result.items.map(\.sourceURL)).count == 5
		else { throw CountryNewsError.invalidResponse }
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		let today = calendar.startOfDay(for: now)
		let earliest = calendar.date(byAdding: .day, value: -7, to: today)!
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.isLenient = false
		for item in result.items {
			guard
				boundedText(item.title, limit: 256),
				boundedText(item.summary, limit: 2000),
				item.publishedDate.count == 10,
				let date = formatter.date(from: item.publishedDate),
				formatter.string(from: date) == item.publishedDate,
				date >= earliest,
				date <= today,
				item.sourceURL.utf8.count <= 2048,
				let url = URLComponents(string: item.sourceURL),
				url.scheme == "https" || url.scheme == "http",
				let host = url.host,
				!host.isEmpty,
				url.user == nil,
				url.password == nil
			else { throw CountryNewsError.invalidResponse }
		}
		return result
	}

	private static func boundedText(_ text: String, limit: Int) -> Bool {
		!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= limit
	}
}
