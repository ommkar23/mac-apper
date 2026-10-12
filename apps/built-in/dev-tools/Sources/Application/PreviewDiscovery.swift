// @frontmatter:start
// Selects a public, main-actor SwiftUI preview factory from compiler JSON ASTs and verifies it is excluded from production compilation.
// @frontmatter:end
import Foundation

struct PreviewDiscovery {
	enum Failure: String, Error {
		case missing_preview, ambiguous_preview, invalid_preview_factory, preview_in_production

		func diagnostic(sourcePath: String) -> String {
			let explanation: String
			switch self {
			case .missing_preview:
				explanation =
					"No preview factory was found in the selected file. Add exactly one factory there; a #Preview macro or a comment is not sufficient."
			case .ambiguous_preview:
				explanation =
					"More than one preview factory was found in the selected file. Keep exactly one apperPreview_NAME factory in that file or select a different file."
			case .invalid_preview_factory:
				explanation =
					"The factory must be top-level, public, @MainActor, synchronous, nonthrowing, and zero-argument, returning some View. Remove generic parameters and match the example signature."
			case .preview_in_production:
				explanation =
					"The factory is still present when compiling without MAC_APPER_PREVIEW. This describes code visibility, not whether Preview is being used during development. Wrap only the preview factory declaration and body in #if MAC_APPER_PREVIEW ... #endif. Do not use #if DEBUG or #if os(macOS) as a substitute."
			}
			return """
				\(rawValue): \(sourcePath)
				\(explanation)
				Keep the normal view outside the preview-only guard. Adapt this example to your view/model and desired state; do not add a second factory if one already exists. Retry preview after correcting the selected file.

				```swift
				#if MAC_APPER_PREVIEW
				@MainActor
				public func apperPreview_Example() -> some View {
				    let model = ApplicationModel()
				    model.title = "Preview state" // Set representative model data here.
				    return ApplicationRoot(model: model)
				}
				#endif
				```
				"""
		}
	}

	static func select(previewAST: String, productionAST: String) throws -> String {
		func items(_ value: String) throws -> [[String: Any]] {
			guard
				let ast = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
				ast["_kind"] as? String == "source_file",
				let items = ast["items"] as? [[String: Any]]
			else { throw Failure.invalid_preview_factory }
			return items
		}
		func name(_ item: [String: Any]) -> String? {
			guard
				item["_kind"] as? String == "func_decl",
				let declaration = item["name"] as? [String: Any],
				let base = declaration["base_name"] as? [String: Any],
				let name = base["name"] as? String,
				name.hasPrefix("apperPreview_")
			else { return nil }
			return name
		}
		let candidates = try items(previewAST).filter { name($0) != nil }
		guard
			!candidates.isEmpty
		else { throw Failure.missing_preview }
		guard
			candidates.count == 1
		else { throw Failure.ambiguous_preview }
		let function = candidates[0]
		guard
			let name = name(function),
			name.utf8.count <= 128,
			name.utf8.allSatisfy({
				(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
			}),
			function["access"] as? String == "public",
			function["async"] as? Bool != true,
			function["thrown_type"] as? String == "",
			function["generic_params"] == nil,
			let params = function["params"] as? [String: Any],
			params["params"] == nil,
			let attrs = function["attrs"] as? [[String: Any]],
			attrs.contains(where: {
				$0["_kind"] as? String == "custom_attr" && $0["type"] as? String == "$sScMD"
			}),
			let opaque = function["opaque_result_decl"] as? [String: Any],
			let requirements = opaque["reqs"] as? [[String: Any]],
			requirements.contains(where: {
				["s:7SwiftUI4ViewP", "s:11SwiftUICore4ViewP"].contains($0["protocol"] as? String ?? "")
			})
		else { throw Failure.invalid_preview_factory }
		let production = try items(productionAST)
		guard
			!production.contains(where: { selfName($0) == name })
		else { throw Failure.preview_in_production }
		return name
	}

	private static func selfName(_ item: [String: Any]) -> String? {
		guard
			item["_kind"] as? String == "func_decl",
			let name = item["name"] as? [String: Any],
			let base = name["base_name"] as? [String: Any]
		else { return nil }
		return base["name"] as? String
	}
}
