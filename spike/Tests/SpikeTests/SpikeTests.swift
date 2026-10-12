import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpikeFixtures

@Test func fixtureIdentityAndMinimalReproduction() {
	#expect(Set(Fixture.allCases.map(\.rawValue)).count == Fixture.allCases.count)
	#expect(Fixture.allCases.contains(.counter))
	#expect(Fixture.allCases.contains(.symbols))
	#expect(Canvas.width == 460)
	#expect(Canvas.height == 430)
}

@Test func bundledPNGIsRealAndDistinctFromAssetCatalog() throws {
	let data = try Data(contentsOf: Fixture.bundledImageURL)
	#expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
	#expect(Fixture.bundledImageURL.pathExtension == "png")
	#expect(!Fixture.allCases.map(\.rawValue).contains("asset-catalog"))
}

@Test @MainActor func everyFixtureProducesBoundedImageRendererPNGDimensions() throws {
	_ = NSApplication.shared
	// This confirms image production, deliberately not visual support.
	for fixture in Fixture.allCases {
		let renderer = ImageRenderer(content: fixture.content(localImageURL: Fixture.bundledImageURL))
		renderer.proposedSize = ProposedViewSize(
			width: CGFloat(Canvas.width), height: CGFloat(Canvas.height))
		renderer.scale = 1
		let image = try #require(renderer.cgImage)
		#expect(image.width == Canvas.width)
		#expect(image.height == Canvas.height)
	}
}
