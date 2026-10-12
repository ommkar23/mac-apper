// @frontmatter:start
// Renders a PNG chart of Swift source line-count distribution from bounded JSON input.
// @frontmatter:end
import AppKit
import Charts
import Foundation
import SwiftUI

struct Bucket: Identifiable {
	let label: String
	let count: Int
	var id: String { label }
}

@MainActor
@main
enum SwiftLinesChartTool {
	static func main() throws {
		guard CommandLine.arguments.count == 3 else {
			throw ChartError.invalidInput
		}
		let input = URL(fileURLWithPath: CommandLine.arguments[1])
		let output = URL(fileURLWithPath: CommandLine.arguments[2])
		let data = try Data(contentsOf: input)
		guard data.count <= 2_000_000 else { throw ChartError.invalidInput }
		let lines = try JSONDecoder().decode([Int].self, from: data)
		guard lines.count <= 100_000, lines.allSatisfy({ $0 >= 0 }) else {
			throw ChartError.invalidInput
		}
		let distribution = buckets(for: lines)
		let chart = VStack(alignment: .leading, spacing: 24) {
			Text("Swift lines per source file")
				.font(.system(size: 32, weight: .bold))
			Text("\(lines.count) files · \(lines.reduce(0, +)) lines")
				.font(.system(size: 18))
			Chart(distribution) { bucket in
				BarMark(
					x: .value("Files", bucket.count),
					y: .value("Lines per file", bucket.label)
				)
				.foregroundStyle(.blue)
			}
			.chartYScale(domain: distribution.map(\.label))
			.chartYAxisLabel("Lines per file")
			.chartXAxisLabel("Files")
		}
		.padding(48)
		.frame(width: 1100, height: CGFloat(max(680, distribution.count * 36 + 220)))
		.background(Color.white)
		let renderer = ImageRenderer(content: chart)
		renderer.scale = 2
		guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
			let bitmap = NSBitmapImageRep(data: tiff),
			let png = bitmap.representation(using: .png, properties: [:])
		else { throw ChartError.renderFailed }
		try png.write(to: output, options: .atomic)
	}

	static func buckets(for lines: [Int]) -> [Bucket] {
		let largest = (lines.filter { $0 < 2000 }.max() ?? 0) / 20
		var result = (0...largest).map { index in
			Bucket(label: "\(index * 20)–\(index * 20 + 19)", count: 0)
		}
		var overflow = 0
		for length in lines {
			if length >= 2000 {
				overflow += 1
			} else {
				let index = length / 20
				result[index] = Bucket(label: result[index].label, count: result[index].count + 1)
			}
		}
		if overflow > 0 { result.append(Bucket(label: "2000+", count: overflow)) }
		return result
	}
}

private enum ChartError: Error {
	case invalidInput
	case renderFailed
}
