// @frontmatter:start
// Configures the Agent XPC service with its catalog, Pi runtime, workspace manager, and listener.
// @frontmatter:end
import Foundation

public enum AgentXPCServiceMain {
	public static func processConfiguration(executable: URL? = PiExecutableLocator.locate())
		-> PiProcessConfiguration
	{
		.init(
			executable: executable, provider: "openai-codex", model: "gpt-6.1-sol", thinking: "medium")
	}

	@MainActor public static func run() throws {
		let hostContents = packagedHostContents()
		let integrationCatalog =
			try hostContents.map {
				try AgentIntegrationCatalog.load(
					from: $0.appendingPathComponent("Resources/IntegrationCatalog.json"))
			} ?? AgentIntegrationCatalog.defaultCatalog()
		let integrationRoot = hostContents ?? AgentIntegrationCatalog.defaultRootURL()
		let projectsRoot = AgentPaths.projectsRoot()
		let preparations = SessionPreparationRegistry()
		let sessions = AgentProcessManager(
			projectsRoot: projectsRoot, preparations: preparations
		) { _ in
			PiRPCProcess(
				configuration: processConfiguration(),
				integrationCatalog: integrationCatalog,
				integrationRootURL: integrationRoot)
		}
		let controllers = ControllerFactory(
			sessions: sessions,
			workspace: WorkspaceDataManager(projectsRoot: projectsRoot, preparations: preparations))
		OpenXPCGeneratedService.listen(controllers: controllers.controllers())
	}

	private static func packagedHostContents() -> URL? {
		let serviceBundle = Bundle.main.bundleURL.standardizedFileURL
		guard
			serviceBundle.pathExtension == "xpc"
		else { return nil }
		let contents = serviceBundle.deletingLastPathComponent().deletingLastPathComponent()
		let catalog = contents.appendingPathComponent("Resources/IntegrationCatalog.json")
		return FileManager.default.isReadableFile(atPath: catalog.path) ? contents : nil
	}
}
