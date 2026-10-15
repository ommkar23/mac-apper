// @frontmatter:start
// Validates DevTools' planned OpenXPC tool specification and bounded plan records.
// @frontmatter:end
import Foundation
import OpenXPCSpecification
import Testing

private let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	.deletingLastPathComponent().deletingLastPathComponent()

@Test func devToolsProductionUsesGeneratedListenerAndPiClient() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.components(separatedBy: ".plugin(name: \"OpenXPCBuildPlugin\"").count == 3)
	#expect(!manifest.contains("OpenXPCGeneratorV2"))
	#expect(!manifest.contains("OpenXPCV2BuildPlugin"))
	#expect(!manifest.contains("plugins: [.plugin(name: \"DevToolsBuildPlugin\")"))
	let entry = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/main.swift"), encoding: .utf8)
	#expect(entry.contains("OpenXPCGeneratedService.listen(controllers:"))
	#expect(!entry.contains("@main"))
}

@Test func devToolsOpenXPCSpecDefinesBoundedPreviewPathTool() throws {
	let yaml = try String(
		contentsOf: packageRoot.appendingPathComponent("OpenXPC.yaml"), encoding: .utf8)
	let generation = try String(
		contentsOf: packageRoot.appendingPathComponent("OpenXPCGen.yaml"), encoding: .utf8)
	let specification = try OpenXPCSpecification(
		contractYAML: yaml, generationYAML: generation)
	#expect(specification.subscriptions.isEmpty)
	#expect(specification.service.identifier == "com.macapper.dev-tools.xpc")
	#expect(specification.service.target == "DevToolsApplication")
	#expect(specification.service.maxPayloadBytes == 65_536)
	#expect(specification.service.timeoutSeconds >= 300)
	let operations = specification.dataSchema.operations
	#expect(
		Set(operations.map(\.name)) == ["build", "test", "run", "preview", "plan", "set_app_name"])
	for operation in operations {
		#expect(operation.tool != nil)
	}
	#expect(specification.clients.count == 1)
	let agent = try #require(specification.clients.first { $0.target == "DevToolsTerminalClient" })
	#expect(agent.generation == .agentClient)
	#expect(Set(agent.operations) == ["build", "test", "run", "preview", "plan", "set_app_name"])
	let schema = specification.dataSchema
	let runResult = try #require(schema.types.first { $0.name == "RunResult" })
	#expect(Set(runResult.fields.map(\.name)) == ["summary", "target", "relativePath"])
	let preview = try #require(schema.types.first { $0.name == "PreviewResult" })
	#expect(preview.fields.first { $0.name == "status" }?.type == "string")
	#expect(preview.fields.first { $0.name == "summary" }?.type == "string")
	for name in ["width", "height", "artifact"] {
		#expect(preview.fields.first { $0.name == name }?.optional == true)
	}
	let planRequest = try #require(schema.types.first { $0.name == "PlanRequest" })
	#expect(planRequest.fields.first { $0.name == "action" }?.maxLength == 32)
	#expect(planRequest.fields.first { $0.name == "tasks" }?.maxItems == 100)
	#expect(planRequest.fields.first { $0.name == "ids" }?.maxItems == 100)
	for name in [
		"BuildRequest", "TestRequest", "RunRequest", "PreviewRequest", "PlanRequest",
		"SetAppNameRequest",
	] {
		let request = try #require(schema.types.first { $0.name == name })
		#expect(request.fields.first { $0.name == "projectRoot" }?.injected == "projectRoot")
	}
	let task = try #require(schema.types.first { $0.name == "PlanTask" })
	#expect(task.fields.first { $0.name == "id" }?.maxLength == 64)
	#expect(task.fields.first { $0.name == "title" }?.maxLength == 256)
	let planTool = try #require(operations.first { $0.name == "plan" }?.tool)
	let parameters = try #require(planTool.parametersJSON)
	#expect(parameters.contains("add_plan"))
	#expect(parameters.contains("get_tasks"))
	#expect(parameters.contains("update_tasks"))
	#expect(parameters.contains("delete_tasks"))
	let parameterSchema = try #require(
		JSONSerialization.jsonObject(with: Data(parameters.utf8)) as? [String: Any])
	let branches = try #require(parameterSchema["oneOf"] as? [[String: Any]])
	let creation = try #require(
		branches.first { branch in
			let properties = branch["properties"] as? [String: Any]
			let action = properties?["action"] as? [String: Any]
			return action?["const"] as? String == "add_plan"
		})
	let forbidden = try #require(creation["not"] as? [String: Any])
	#expect(forbidden["required"] as? [String] == ["ids"])
	#expect(creation["required"] == nil)
	let service = try OpenXPCSourceGenerator.generate(
		spec: specification, target: "DevToolsApplication", serviceDispatch: .controllers)
	#expect(service.swift.contains("public struct Controllers: Sendable"))
	#expect(!service.swift.contains("public struct Handlers: Sendable"))
	for name in [
		"BuildResult", "TestResult", "RunResult", "PreviewResult", "PlanResult", "SetAppNameResult",
	] {
		#expect(service.swift.contains("public struct \(name):"))
	}
	let client = try OpenXPCSourceGenerator.generate(
		spec: specification, target: "DevToolsTerminalClient")
	#expect(client.swift.contains("PlanRequest"))
	#expect(client.swift.contains("TestRequest"))
	#expect(client.piExtension?.contains("name: \"test\"") == true)
	let testResult = try #require(schema.types.first { $0.name == "TestResult" })
	#expect(testResult.fields.first { $0.name == "diagnostics" }?.maxLength == 4096)
	#expect(testResult.fields.first { $0.name == "exitCode" }?.optional == true)
	let testTool = try #require(operations.first { $0.name == "test" }?.tool)
	#expect(testTool.description.contains("Check status and exitCode, not transport success"))
	#expect(client.piExtension?.contains("add_plan") == true)
	#expect(client.piExtension?.contains("name: \"preview\"") == true)
	#expect(client.piExtension?.contains("imageArtifact") == false)
	#expect(client.piExtension?.contains("type: \"image\"") == false)
	#expect(client.piExtension?.contains("details: { result }") == true)
	let previewTool = try #require(operations.first { $0.name == "preview" }?.tool)
	#expect(previewTool.imageArtifact == nil)
	#expect(previewTool.description.contains("artifact.reviewPath"))
	#expect(previewTool.description.contains("optional"))
	#expect(previewTool.description.contains("read"))
	#expect(previewTool.description.contains("text only"))
	let artifact = try #require(schema.types.first { $0.name == "PreviewArtifact" })
	for name in ["relativePath", "reviewPath"] {
		#expect(artifact.fields.first { $0.name == name }?.maxLength == 4096)
	}
	#expect(previewTool.description.contains("public func apperPreview_Example() -> some View"))
	#expect(previewTool.description.contains("not that Preview was called in production"))
	#expect(client.piExtension?.contains("public func apperPreview_Example() -> some View") == true)
	#expect(previewTool.parametersJSON?.contains("screenSize") == true)
	#expect(client.piExtension?.contains("OPENXPC_PROJECT_ROOT") == true)
	let namingRequest = try #require(schema.types.first { $0.name == "SetAppNameRequest" })
	#expect(namingRequest.fields.first { $0.name == "projectRoot" }?.maxLength == 4096)
	#expect(namingRequest.fields.first { $0.name == "name" }?.maxLength == 256)
	let namingResult = try #require(schema.types.first { $0.name == "SetAppNameResult" })
	#expect(namingResult.fields.first { $0.name == "name" }?.maxLength == 256)
	#expect(namingResult.fields.first { $0.name == "summary" }?.maxLength == 1024)
	let namingTool = try #require(operations.first { $0.name == "set_app_name" }?.tool)
	let namingJSON = try #require(namingTool.parametersJSON)
	let namingSchema = try #require(
		JSONSerialization.jsonObject(with: Data(namingJSON.utf8)) as? [String: Any])
	#expect(namingSchema["required"] as? [String] == ["name"])
	#expect(namingSchema["additionalProperties"] as? Bool == false)
	let namingProperties = try #require(namingSchema["properties"] as? [String: [String: Any]])
	#expect(Set(namingProperties.keys) == ["name"])
	#expect(namingProperties["name"]?["minLength"] as? Int == 1)
	#expect(namingProperties["name"]?["maxLength"] as? Int == 64)
	#expect(namingTool.description.contains("Does not build, repackage"))
	#expect(service.swift.contains("public protocol OpenXPCSet_app_nameController"))
	#expect(service.swift.contains("controllers.set_app_name.handle"))
	#expect(client.piExtension?.components(separatedBy: "name: \"set_app_name\"").count == 2)
}
