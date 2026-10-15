// @frontmatter:start
// Discovers guarded preview factories with the toolchain parser, stages isolated SwiftPM builds, and validates rendered PNG artifacts.
// @frontmatter:end
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreviewRendering: Sendable {
	enum Failure: Error {
		case invalidScreenSize, missingPreviewResource, invalidSource, invalidArtifact
		case processFailed(String)
	}
	let xcrunURL: URL
	let environment: [String: String]
	// Internal deterministic test seam; nil always uses the production owned process path.
	typealias ProcessRunner = @Sendable (URL, [String], URL, Duration, Int) async throws -> String
	var processRunner: ProcessRunner? = nil

	func render(
		project: ResolvedProject, sessionID: UUID, sourcePath: String, size: PreviewScreenSize?
	) async throws
		-> PreviewResult
	{
		let width = size?.width ?? 640, height = size?.height ?? 480
		guard
			(64...2048).contains(width),
			(64...2048).contains(height),
			width * height <= 2_097_152
		else { throw Failure.invalidScreenSize }
		let requestID = UUID().uuidString.lowercased()
		let workspacePath = ".mac-apper/PreviewBuild/\(requestID)"
		let workspace = try project.scope.resolve(workspacePath)
		let manager = FileManager.default
		try manager.createDirectory(
			at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		var childCleanupUncertain = false
		defer { if !childCleanupUncertain { try? manager.removeItem(at: workspace) } }
		// Mark uncertainty before either request-file defer can run.
		func run(
			_ executable: URL, arguments: [String], directory: URL, timeout: Duration,
			outputLimit: Int = 65_536
		) async throws -> String {
			do {
				return try await self.run(
					executable, arguments: arguments, directory: directory, timeout: timeout,
					outputLimit: outputLimit)
			} catch let error as OwnedProcess.Failure
				where error == .cleanupFailed || error == .reapFailed
			{
				childCleanupUncertain = true
				throw error
			}
		}
		// Freeze sources before discovery so the selected declaration and build use the same snapshot.
		var budget = 16_777_216
		var entries = 0
		try copySources(
			project.scope.resolve("Sources"), to: workspace.appendingPathComponent("Sources"),
			budget: &budget, entries: &entries, depth: 0)
		let tests = try project.scope.resolve("Tests")
		if manager.fileExists(atPath: tests.path) {
			try copySources(
				tests, to: workspace.appendingPathComponent("Tests"), budget: &budget, entries: &entries,
				depth: 0)
		}
		let manifest = try project.scope.resolve("Package.swift")
		try copyFile(manifest, to: workspace.appendingPathComponent("Package.swift"), budget: &budget)
		let lockfile = try project.scope.resolve("Package.resolved")
		if manager.fileExists(atPath: lockfile.path) {
			try copyFile(
				lockfile, to: workspace.appendingPathComponent("Package.resolved"), budget: &budget)
		}
		let source = workspace.appendingPathComponent(sourcePath)
		let build = workspace.appendingPathComponent("Build")
		_ = try await run(
			xcrunURL,
			arguments: [
				"swift", "build", "--target", "AppViews", "--scratch-path", build.path, "-Xswiftc",
				"-DMAC_APPER_PREVIEW",
			], directory: workspace, timeout: .seconds(120))
		let productsPath = try await run(
			xcrunURL, arguments: ["swift", "build", "--scratch-path", build.path, "--show-bin-path"],
			directory: workspace, timeout: .seconds(10), outputLimit: 4096
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let products = URL(fileURLWithPath: productsPath).resolvingSymlinksInPath()
		guard
			products.path.hasPrefix(build.resolvingSymlinksInPath().path + "/")
		else { throw Failure.invalidArtifact }
		// Do not let the compiler import a previously built copy of its own AppViews module.
		let dependencyModules = workspace.appendingPathComponent("DependencyModules")
		try manager.createDirectory(at: dependencyModules, withIntermediateDirectories: true)
		// Swift Build places module directories beside products; native SwiftPM used Modules/.
		let legacyModules = products.appendingPathComponent("Modules")
		let modules =
			manager.fileExists(atPath: legacyModules.path)
			? legacyModules : products
		for module in try manager.contentsOfDirectory(
			at: modules, includingPropertiesForKeys: [.isDirectoryKey])
		where !module.lastPathComponent.hasPrefix("AppViews.")
			&& ["swiftmodule", "swiftdoc", "swiftsourceinfo"].contains(module.pathExtension)
		{
			let destination = dependencyModules.appendingPathComponent(module.lastPathComponent)
			if try module.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
				try copySources(module, to: destination, budget: &budget, entries: &entries, depth: 0)
			} else {
				try copyFile(module, to: destination, budget: &budget)
			}
		}
		let sdk = try await run(
			xcrunURL, arguments: ["--show-sdk-path"], directory: workspace, timeout: .seconds(10)
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let otherSources = try sourceFiles(workspace.appendingPathComponent("Sources/AppViews")).filter
		{
			URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL
				!= source.resolvingSymlinksInPath().standardizedFileURL
		}
		let astArguments =
			[
				"swiftc", "-frontend", "-dump-ast", "-dump-ast-format", "json", "-parse-as-library",
				"-suppress-warnings", "-sdk", sdk, "-module-name", "AppViews", "-I", dependencyModules.path,
				"-primary-file", source.path,
			] + otherSources
		let previewAST = try await run(
			xcrunURL, arguments: astArguments + ["-D", "MAC_APPER_PREVIEW"], directory: workspace,
			timeout: .seconds(30), outputLimit: 4_194_304)
		let productionAST = try await run(
			xcrunURL, arguments: astArguments, directory: workspace, timeout: .seconds(30),
			outputLimit: 4_194_304)
		let factory = try PreviewDiscovery.select(previewAST: previewAST, productionAST: productionAST)
		guard
			factory.hasPrefix("apperPreview_"),
			factory.utf8.count <= 128,
			factory.utf8.allSatisfy({
				(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
			})
		else { throw Failure.invalidSource }
		let entry = workspace.appendingPathComponent("Sources/ApperSnapshot")
		guard
			!manager.fileExists(atPath: entry.path)
		else { throw Failure.invalidSource }
		try manager.createDirectory(at: entry, withIntermediateDirectories: true)
		let template = try String(contentsOf: resource("PreviewRenderer"), encoding: .utf8)
		try template.replacingOccurrences(of: "__APPER_PREVIEW_FACTORY__", with: factory)
			.write(to: entry.appendingPathComponent("Snapshot.swift"), atomically: true, encoding: .utf8)
		let package = workspace.appendingPathComponent("Package.swift")
		var packageSource = try String(contentsOf: package, encoding: .utf8)
		packageSource += """

			#if os(macOS)
			package.targets.append(.executableTarget(name: "ApperSnapshot", dependencies: ["AppModel", "AppViews"]))
			package.products.append(.executable(name: "ApperSnapshot", targets: ["ApperSnapshot"]))
			#endif
			"""
		try packageSource.write(to: package, atomically: true, encoding: .utf8)
		_ = try await run(
			xcrunURL,
			arguments: [
				"swift", "build", "--product", "ApperSnapshot", "--scratch-path", build.path, "-Xswiftc",
				"-DMAC_APPER_PREVIEW",
			], directory: workspace, timeout: .seconds(120))
		let artifactPath = ".mac-apper/Artifacts/\(requestID)/render.png"
		let artifact = try project.scope.resolve(artifactPath)
		try manager.createDirectory(
			at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		var complete = false
		defer {
			if !complete && !childCleanupUncertain {
				try? manager.removeItem(at: artifact.deletingLastPathComponent())
			}
		}
		let executable = products.appendingPathComponent("ApperSnapshot").resolvingSymlinksInPath()
		guard
			executable.path.hasPrefix(build.resolvingSymlinksInPath().path + "/"),
			manager.isExecutableFile(atPath: executable.path)
		else { throw Failure.invalidArtifact }
		_ = try await run(
			executable, arguments: [String(width), String(height), artifact.path], directory: workspace,
			timeout: .seconds(15))
		_ = try project.scope.resolve(artifactPath)
		let values = try artifact.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let count = values.fileSize,
			(1...2_097_152).contains(count)
		else { throw Failure.invalidArtifact }
		let data = try Data(contentsOf: artifact)
		guard
			data.count <= 2_097_152,
			let image = CGImageSourceCreateWithData(data as CFData, nil),
			CGImageSourceGetCount(image) == 1,
			CGImageSourceGetType(image) as String? == UTType.png.identifier,
			let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any],
			properties[kCGImagePropertyPixelWidth as String] as? Int == width,
			properties[kCGImagePropertyPixelHeight as String] as? Int == height,
			CGImageSourceCreateImageAtIndex(image, 0, nil) != nil
		else { throw Failure.invalidArtifact }
		guard
			let projectID = UUID(uuidString: project.manifest.appID)
		else { throw Failure.invalidSource }
		let review = try PreviewArchive.save(
			data, projectsRoot: project.scope.root.deletingLastPathComponent(),
			projectID: projectID, sessionID: sessionID)
		complete = true
		return try PreviewResult(
			status: "rendered", summary: "Rendered \(factory) at \(width)x\(height) in light appearance.",
			width: width, height: height,
			artifact: PreviewArtifact(relativePath: artifactPath, reviewPath: review.path, kind: "png"))
	}

	private func sourceFiles(_ directory: URL) throws -> [String] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: directory, includingPropertiesForKeys: nil)
		else { throw Failure.invalidSource }
		return enumerator.compactMap {
			($0 as? URL).flatMap { $0.pathExtension == "swift" ? $0.path : nil }
		}.sorted()
	}

	private func resource(_ name: String) throws -> URL {
		if let root = Bundle.main.resourceURL,
			let bundle = Bundle(url: root.appendingPathComponent("DevTools_DevToolsApplication.bundle")),
			let url = bundle.url(forResource: name, withExtension: "swift")
		{
			return url
		}
		// SwiftPM test executables have no Contents/Info.plist; deployed services must not fall back to source-tree resources.
		guard
			!FileManager.default.fileExists(
				atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist").path),
			let url = Bundle.module.url(forResource: name, withExtension: "swift")
		else { throw Failure.missingPreviewResource }
		return url
	}

	private func run(
		_ executable: URL, arguments: [String], directory: URL, timeout: Duration,
		outputLimit: Int = 65_536
	) async throws -> String {
		try Task.checkCancellation()
		if let processRunner {
			return try await processRunner(executable, arguments, directory, timeout, outputLimit)
		}
		let command = try SwiftToolchain.command(
			executable: executable, arguments: arguments, environment: environment)
		let process = try OwnedProcess(
			executable: command.executable, arguments: command.arguments, directory: directory,
			environment: command.environment,
			outputLimit: outputLimit)
		let status = try await process.wait(timeout: timeout)
		guard
			status == 0
		else {
			throw Failure.processFailed(
				String(SwiftToolchain.compactDiagnostics(process.output).suffix(3500)))
		}
		return process.output
	}

	private func copyFile(_ source: URL, to destination: URL, budget: inout Int) throws {
		let values = try source.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let size = values.fileSize,
			size <= 1_048_576,
			size <= budget
		else { throw Failure.invalidSource }
		budget -= size
		try FileManager.default.copyItem(at: source, to: destination)
	}

	private func copySources(
		_ source: URL, to destination: URL, budget: inout Int, entries: inout Int, depth: Int
	) throws {
		let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		guard
			values.isDirectory == true,
			values.isSymbolicLink != true,
			depth <= 12
		else { throw Failure.invalidSource }
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		for child in try FileManager.default.contentsOfDirectory(
			at: source, includingPropertiesForKeys: nil)
		{
			entries += 1
			guard
				entries <= 1024
			else { throw Failure.invalidSource }
			let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			guard
				values.isSymbolicLink != true
			else { throw Failure.invalidSource }
			let target = destination.appendingPathComponent(child.lastPathComponent)
			if values.isDirectory == true {
				try copySources(child, to: target, budget: &budget, entries: &entries, depth: depth + 1)
			} else {
				try copyFile(child, to: target, budget: &budget)
			}
		}
	}
}
