// @frontmatter:start
// Supplies the fixed Chat and Create presets through the typed Agent service operation.
// @frontmatter:end
import Foundation

struct ListPresetsController: OpenXPCListPresetsController {
	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PresetListRequest) async throws
		-> PresetListResponse
	{
		try PresetListResponse(
			descriptors: AgentCatalog.descriptors.map {
				try AgentPresetRecord(
					id: $0.id, displayName: $0.displayName, runtimeMode: $0.runtimeMode.rawValue)
			})
	}
}
