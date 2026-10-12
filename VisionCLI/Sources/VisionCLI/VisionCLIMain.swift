// @frontmatter:start
// Exposes JSON stdin/stdout image verification, safe credential checks, model recommendations, and deterministic exit codes for scenario callers.
// @frontmatter:end
import Darwin
import Foundation
import VisionCore

@main struct VisionCLIMain {
	static func main() async {
		var identity: UUID?
		do {
			let args = Array(CommandLine.arguments.dropFirst())
			if args.isEmpty || args == ["--help"] {
				print(
					"""
					Usage: vision-cli verify [--env-file /absolute/.env] < request.json
					       vision-cli check-config [--env-file /absolute/.env]
					       vision-cli models
					One bounded JSON object on stdin; one JSON result line on stdout.
					Exit: 0 pass, 1 fail, 2 uncertain, 3 operational/configuration error.
					GEMINI_API_KEY overrides the private VisionCLI/.env file.
					verify uploads the image/criteria to Google and may incur charges.
					""")
				return
			}
			if args == ["models"] {
				try output([
					"researchedAt": "2026-10-05", "defaultModel": "gemini-3.8-flash",
					"models": [
						["id": "gemini-3.8-flash", "status": "stable", "purpose": "Default screenshot review"],
						[
							"id": "gemini-3.5-flash-lite", "status": "stable",
							"purpose": "Lower-latency/cost option",
						],
						[
							"id": "gemini-3.1-pro-preview", "status": "preview",
							"purpose": "Advanced reasoning alternative",
						],
					],
				])
				return
			}
			guard
				let command = args.first,
				["verify", "check-config"].contains(command),
				args.count == 1 || (args.count == 3 && args[1] == "--env-file" && args[2].hasPrefix("/"))
			else {
				throw VisionFailure(
					.invalid_request,
					"Use --help for supported commands; --env-file requires an absolute path.")
			}
			let file = args.count == 3 ? URL(fileURLWithPath: args[2]) : defaultEnvFile()
			if command == "check-config" {
				let credentials = try Credentials.load(
					environment: ProcessInfo.processInfo.environment, file: file)
				try output(["configured": true, "source": credentials.source, "networkChecked": false])
				return
			}
			var data = Data()
			while data.count <= 65_536 {
				let chunk =
					try FileHandle.standardInput.read(upToCount: min(4096, 65_537 - data.count)) ?? Data()
				if chunk.isEmpty { break }
				data.append(chunk)
			}
			let request = try VisionRequest.decode(data)
			identity = request.requestID
			let image = try LoadedImage.load(path: request.imagePath)
			let credentials = try Credentials.load(
				environment: ProcessInfo.processInfo.environment, file: file)
			let result = try await GeminiClient(apiKey: credentials.value, transport: LiveTransport())
				.verify(request, image: image)
			let encoded = try JSONEncoder().encode(result)
			FileHandle.standardOutput.write(encoded + Data([10]))
			exit(result.verdict.exitCode)
		} catch {
			let failure =
				error as? VisionFailure
				?? VisionFailure(
					.network_error, "Verification failed; internal details and credentials are not logged.")
			var record: [String: Any] = [
				"version": 1, "status": "error",
				"error": ["code": failure.code.rawValue, "message": failure.message],
			]
			record["requestID"] = identity.map { $0.uuidString as Any } ?? NSNull()
			try? output(record)
			exit(3)
		}
	}

	private static func output(_ object: [String: Any]) throws {
		FileHandle.standardOutput.write(
			try JSONSerialization.data(withJSONObject: object, options: .sortedKeys) + Data([10]))
	}

	private static func defaultEnvFile() -> URL? {
		guard
			var directory = Bundle.main.executableURL?.resolvingSymlinksInPath()
				.deletingLastPathComponent()
		else { return nil }
		for _ in 0..<8 {
			if directory.lastPathComponent == "VisionCLI",
				FileManager.default.fileExists(
					atPath: directory.appendingPathComponent("Package.swift").path)
			{
				return directory.appendingPathComponent(".env")
			}
			let parent = directory.deletingLastPathComponent()
			if parent == directory { break }
			directory = parent
		}
		return nil
	}
}
