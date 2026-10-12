import AppKit
import SwiftUI

public enum Canvas {
	public static let width = 460
	public static let height = 430
}

public enum Fixture: String, CaseIterable, Sendable {
	case textShapes = "text-shapes"
	case symbols
	case bundledPNG = "bundled-png"
	case localPNG = "local-png"
	case automaticLabel = "automatic-label"
	case plainLabel = "plain-label"
	case borderedLabel = "bordered-label"
	case borderlessLabel = "borderless-label"
	case prominentLabel = "prominent-label"
	case automaticText = "automatic-text"
	case plainText = "plain-text"
	case borderedText = "bordered-text"
	case borderlessText = "borderless-text"
	case prominentText = "prominent-text"
	case counter
	case appKit = "appkit-representable"

	public static var bundledImageURL: URL {
		Bundle.module.url(forResource: "checker", withExtension: "png")!
	}

	@MainActor public func content(localImageURL: URL) -> some View {
		VStack(spacing: 24) {
			Text(rawValue).font(.headline)
			body(localImageURL: localImageURL)
		}
		.frame(width: CGFloat(Canvas.width), height: CGFloat(Canvas.height))
		.environment(\.colorScheme, .light)
		.transaction {
			$0.disablesAnimations = true; $0.animation = nil
		}
	}

	@MainActor @ViewBuilder private func body(localImageURL: URL) -> some View {
		switch self {
		case .textShapes:
			Text("Count: 0").font(.largeTitle)
			HStack {
				Circle().fill(.blue); RoundedRectangle(cornerRadius: 12).fill(.orange)
			}
			.frame(width: 180, height: 64)
		case .symbols:
			HStack(spacing: 24) {
				Image(systemName: "number.square.fill")
				Image(systemName: "plus")
				Image(systemName: "minus")
			}.font(.system(size: 44)).foregroundStyle(.blue)
		case .bundledPNG:
			raster(Self.bundledImageURL)
		case .localPNG:
			raster(localImageURL)
		case .automaticLabel: labeledButtons.buttonStyle(.automatic)
		case .plainLabel: labeledButtons.buttonStyle(.plain)
		case .borderedLabel: labeledButtons.buttonStyle(.bordered)
		case .borderlessLabel: labeledButtons.buttonStyle(.borderless)
		case .prominentLabel: labeledButtons.buttonStyle(.borderedProminent)
		case .automaticText: textButtons.buttonStyle(.automatic)
		case .plainText: textButtons.buttonStyle(.plain)
		case .borderedText: textButtons.buttonStyle(.bordered)
		case .borderlessText: textButtons.buttonStyle(.borderless)
		case .prominentText: textButtons.buttonStyle(.borderedProminent)
		case .counter:
			Image(systemName: "number.square.fill").font(.system(size: 44)).foregroundStyle(.blue)
			Text("0").font(.system(size: 56, weight: .bold))
			labeledButtons.buttonStyle(.bordered).controlSize(.large)
			Button("Reset") {}.buttonStyle(.plain)
		case .appKit:
			NativeControl().frame(width: 240, height: 44)
		}
	}

	@MainActor private var labeledButtons: some View {
		HStack(spacing: 16) {
			Button {
			} label: {
				Label("Increment", systemImage: "plus")
			}
			Button {
			} label: {
				Label("Decrement", systemImage: "minus")
			}
		}.controlSize(.large)
	}

	@MainActor private var textButtons: some View {
		HStack(spacing: 16) {
			Button("Increment") {}
			Button("Decrement") {}
		}.controlSize(.large)
	}

	@MainActor private func raster(_ url: URL) -> some View {
		Image(nsImage: NSImage(contentsOf: url)!)
			.resizable().interpolation(.none).frame(width: 128, height: 128)
	}
}

private struct NativeControl: NSViewRepresentable {
	func makeNSView(context: Context) -> NSButton {
		let button = NSButton(title: "Native AppKit Button", target: nil, action: nil)
		button.bezelStyle = .rounded
		return button
	}
	func updateNSView(_ nsView: NSButton, context: Context) {}
}
