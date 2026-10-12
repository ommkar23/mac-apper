import AppKit
import Foundation
import ImageIO
import Testing
@testable import SpikeFixtures

@Test func reviewCoverageAndConfiguration() throws {
	#expect(ReviewFixture.allCases.count >= 20)
	#expect(Set(ReviewFixture.allCases.map(\.rawValue)).count == ReviewFixture.allCases.count)
	#expect(Fixture.allCases.count == 16)
	let config = ReviewCaptureConfiguration()
	#expect(config.width == 720 && config.height == 540)
	#expect(config.scale == 1 && config.appearance == "aqua")
	#expect(throws: (any Error).self) { try config.validatePNG(Data()) }
	#expect(throws: (any Error).self) {
		try config.validatePNG(Data(repeating: 0, count: config.maximumBytes + 1))
	}
}

@Test @MainActor func ownedReviewCaptureClosesWindowAndValidatesPNG() throws {
	let result = try captureReview(.typography, localImageURL: Fixture.bundledImageURL)
	let config = ReviewCaptureConfiguration()
	try config.validatePNG(result)
	#expect(throws: (any Error).self) { try config.validatePNG(result.dropLast()) }
	#expect(throws: (any Error).self) {
		try config.validatePNG(Data(contentsOf: Fixture.bundledImageURL))
	}
	let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
	let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
	#expect(image.width == config.width && image.height == config.height)
	#expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
}
