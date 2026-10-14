// @frontmatter:start
// Authors offline embedded-WebKit regressions and strict fixture-evidence rejection tests without Pi or remote services.
// @frontmatter:end
import Foundation
import Scenario
import Testing

// Metadata-only validation controls: synthetic JSON is not embedded-browser behavioral proof.
@Test func htViewWebKitMalformedEvidenceOffline() throws {
	let fixture = try ProjectTemporaryDirectory.appending("htview-evidence-fixture.html")
	let valid = HTViewWebKitEvidence(
		title: HTViewHTMLFixture.title, color: HTViewHTMLFixture.expectedColor,
		marker: HTViewHTMLFixture.scriptMarker, clicked: true, rendered: true,
		fileURL: fixture.absoluteString)
	let data = try JSONEncoder().encode(valid)
	try validateHTViewWebKitEvidence(data, fixture: fixture)
	let prettyEncoder = JSONEncoder()
	prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	try validateHTViewWebKitEvidence(prettyEncoder.encode(valid), fixture: fixture)
	let source = try #require(String(data: data, encoding: .utf8))
	for bad in [
		"{}", "null", "not JSON",
		source.replacingOccurrences(of: HTViewHTMLFixture.title, with: "wrong title"),
		source.replacingOccurrences(of: HTViewHTMLFixture.expectedColor, with: "rgb(0, 0, 0)"),
		source.replacingOccurrences(of: HTViewHTMLFixture.scriptMarker, with: "script-pending"),
		source.replacingOccurrences(of: #""clicked":true"#, with: #""clicked":false"#),
		source.replacingOccurrences(of: #""rendered":true"#, with: #""rendered":false"#),
		source.replacingOccurrences(of: #""clicked":true"#, with: #""clicked":1"#),
		source.replacingOccurrences(of: #""rendered":true"#, with: #""rendered":1"#),
		#"{"extra":true,"# + String(source.dropFirst()),
		#"{"clicked":true,"# + String(source.dropFirst()),
		#"{"clicked":false,"# + String(source.dropFirst()),
		#"{"rendered":true,"# + String(source.dropFirst()),
		#"{"\u0063licked":true,"# + String(source.dropFirst()),
	] {
		#expect(throws: (any Error).self) {
			try validateHTViewWebKitEvidence(Data(bad.utf8), fixture: fixture)
		}
	}
	#expect(throws: (any Error).self) {
		try validateHTViewWebKitEvidence(data, fixture: fixture.appendingPathExtension("other"))
	}
	#expect(throws: (any Error).self) {
		try validateHTViewWebKitEvidence(Data(repeating: 32, count: 8193), fixture: fixture)
	}
}

// One sequential test owns all builds. It requires local Aqua/WebKit and standalone Swift/CLT,
// but does not start Pi, MCP, a generated production executable, or the original product GUI.
// The fake AppViews below are regression controls only; the verifier itself never constructs a WKWebView.
@Test @MainActor func htViewEmbeddedWebKitOfflineRegression() async throws {
	let compiler = try SDKCompiler.resolve()
	let manager = FileManager.default
	let directory = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-offline-\(UUID().uuidString)")
	try manager.createDirectory(
		at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: directory) }
	let model = directory.appendingPathComponent("Sources/AppModel")
	let views = directory.appendingPathComponent("Sources/AppViews")
	try manager.createDirectory(at: model, withIntermediateDirectories: true)
	try manager.createDirectory(at: views, withIntermediateDirectories: true)
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "GeneratedFixture", platforms: [.macOS(.v14)], targets: [
	    .target(name: "AppModel", resources: [.process("Resources")]),
	    .target(name: "AppViews", dependencies: ["AppModel"], resources: [.copy("Resources")])])
	""".write(
		to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let resources = model.appendingPathComponent("Resources")
	try manager.createDirectory(at: resources, withIntermediateDirectories: false)
	try HTViewHTMLFixture.html.write(
		to: resources.appendingPathComponent("example.html"), atomically: true, encoding: .utf8)
	let viewResources = views.appendingPathComponent("Resources")
	try manager.createDirectory(at: viewResources, withIntermediateDirectories: false)
	try Data("view-resource-marker".utf8).write(
		to: viewResources.appendingPathComponent("view-example.html"))
	try htViewOfflineModelSource.write(
		to: model.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
	let root = views.appendingPathComponent("Root.swift")
	try htViewOfflineRootSource().write(to: root, atomically: true, encoding: .utf8)
	try await verifyHTViewWebKit(project: directory, compiler: compiler)
	let controlEvidence = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-controls-\(UUID().uuidString)")
	try manager.createDirectory(
		at: controlEvidence, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	print("HTVIEW_CONTROL_RECEIPTS: \(controlEvidence.path)")
	let receipt = directory.appendingPathComponent("control-receipt.txt")
	let receiptSource = htViewOfflineReceiptSource(receipt: receipt)
	let expectedMarker = String(reflecting: HTViewHTMLFixture.scriptMarker)
	let wrongCSS = htViewOfflineDOMMutation(
		"""
		const styled = document.getElementById('inline-style');
		styled.style.color = 'rgb(0, 0, 0)';
		if (getComputedStyle(styled).color === 'rgb(0, 0, 0)') {
		    window.webkit.messageHandlers.htViewControl.postMessage('wrong-css:applied');
		}
		""")
	let ineffectiveClick = htViewOfflineDOMMutation(
		"""
		const original = document.getElementById('script-button');
		const replacement = original.cloneNode(true);
		original.replaceWith(replacement);
		const status = document.getElementById('script-status');
		const before = status.textContent;
		replacement.click();
		if (!original.isConnected && replacement.isConnected && before === \(expectedMarker)
		    && status.textContent === before) {
		    window.webkit.messageHandlers.htViewControl.postMessage('ineffective-click:applied');
		}
		""")
	for (name, source, expectsEvidenceRejection) in [
		(
			"missing-view",
			"""
			import SwiftUI
			import AppModel
			import Foundation
			\(receiptSource)
			public struct ApplicationRoot: View {
			    public init(model: ApplicationModel) { recordHTViewControl("missing-view:applied") }
			    public var body: some View { Text("WKWebView CSS JavaScript decoy") }
			}
			""", false
		),
		("unsupported-regex", htViewOfflineRootSource(badRules: true, receipt: receipt), false),
		("wrong-css", htViewOfflineRootSource(script: wrongCSS, receipt: receipt), true),
		("disabled-js", htViewOfflineRootSource(disabledJavaScript: true, receipt: receipt), false),
		(
			"ineffective-js",
			htViewOfflineRootSource(
				script: """
					const before = document.addEventListener;
					document.addEventListener = function() {};
					if (document.addEventListener !== before) {
					    window.webkit.messageHandlers.htViewControl.postMessage('ineffective-js:applied');
					}
					""", startInjection: true, receipt: receipt), false
		),
		(
			"ineffective-click", htViewOfflineRootSource(script: ineffectiveClick, receipt: receipt), true
		),
	] {
		if manager.fileExists(atPath: receipt.path) { try manager.removeItem(at: receipt) }
		try source.write(to: root, atomically: true, encoding: .utf8)
		var rejection: String?
		do {
			try await verifyHTViewWebKit(project: directory, compiler: compiler)
			Issue.record("Invalid embedded WebKit control unexpectedly passed: \(name)")
		} catch { rejection = String(describing: error) }
		// A receipt is produced only after the control observes its intended mutation in the live host.
		// CSS and click receipts report measured DOM behavior, not merely script-injection intent.
		let metadata = try receipt.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		try #require(metadata.isRegularFile == true && metadata.isSymbolicLink == false)
		try #require((metadata.fileSize ?? Int.max) <= 64)
		let applied = try String(contentsOf: receipt, encoding: .utf8)
		try #require(applied == name + ":applied", "Control mutation not established: \(name)")
		try manager.copyItem(at: receipt, to: controlEvidence.appendingPathComponent(name + ".txt"))
		let message = try #require(rejection, "Control must be rejected after its mutation executes")
		#expect(
			message.contains("fixture assertions failed")
				|| (!expectsEvidenceRejection && message.contains("embedded WebKit host failed")),
			"Controls must fail intended behavior, not compilation/prerequisites: \(name): \(message)")
		print("HTVIEW_CONTROL: \(name) receipt=\(applied) rejected=\(message)")
	}
}

// Document-end injection may precede or follow DOMContentLoaded. Use the fixture's actual
// load marker for readiness, not readyState (which can remain interactive after that event).
private let htViewOfflineModelSource = """
	import Foundation
	import SwiftUI
	@MainActor public final class ApplicationPersistence {
	    public static func inMemory() throws -> ApplicationPersistence { ApplicationPersistence() }
	    public func close() throws {}
	}
	@MainActor public final class ApplicationModel: ObservableObject {
	    @Published public var documentURL: URL?
	    @Published public var errorMessage: String?
	    @Published public var isLoading = false
	    public init(persistence: ApplicationPersistence) {
	        // This must compile and execute using SwiftPM's real processed resource bundle.
	        let example = Bundle.module.url(forResource: "example", withExtension: "html")!
	        precondition((try? String(contentsOf: example, encoding: .utf8))?.contains("htview-script-loaded") == true)
	    }
	    public func openDocument(_ url: URL) {
	        do {
	            let html = try String(contentsOf: url, encoding: .utf8)
	            guard html.contains("<html") else { throw NSError(domain: "InvalidHTML", code: 1) }
	            errorMessage = nil; isLoading = true; documentURL = url
	        } catch {
	            errorMessage = error.localizedDescription; isLoading = false
	        }
	    }
	}
	"""

private func htViewOfflineDOMMutation(_ mutation: String) -> String {
	"""
	(() => {
	    const apply = () => { \(mutation) };
	    if (document.getElementById('script-status')?.textContent === \(String(reflecting: HTViewHTMLFixture.scriptMarker))) {
	        apply();
	    } else {
	        document.addEventListener('DOMContentLoaded', apply, {once: true});
	    }
	})();
	"""
}

private func htViewOfflineReceiptSource(receipt: URL?) -> String {
	guard
		let receipt
	else { return "private func recordHTViewControl(_ value: String) {}" }
	return """
		private func recordHTViewControl(_ value: String) {
		    guard value.utf8.count <= 64 else { return }
		    try? Data(value.utf8).write(to: URL(fileURLWithPath: \(String(reflecting: receipt.path))), options: .withoutOverwriting)
		}
		"""
}

private func htViewOfflineRootSource(
	script: String = "", disabledJavaScript: Bool = false, startInjection: Bool = false,
	badRules: Bool = false, receipt: URL? = nil
) -> String {
	let scriptLiteral = String(reflecting: script)
	return """
		import SwiftUI
		import WebKit
		import AppModel
		import Foundation
		\(htViewOfflineReceiptSource(receipt: receipt))
		@MainActor private final class ControlReceipt: NSObject, WKScriptMessageHandler {
		    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
		        if let value = message.body as? String { recordHTViewControl(value) }
		    }
		}
		@MainActor private struct EmbeddedWeb: NSViewRepresentable {
		    @ObservedObject var model: ApplicationModel
		    func makeCoordinator() -> Navigation { Navigation(model: model) }
		    func makeNSView(context: Context) -> WKWebView {
		        let configuration = WKWebViewConfiguration()
		        configuration.defaultWebpagePreferences.allowsContentJavaScript = \(!disabledJavaScript)
		        if !configuration.defaultWebpagePreferences.allowsContentJavaScript {
		            recordHTViewControl("disabled-js:applied")
		        }
		        configuration.userContentController.add(ControlReceipt(), name: "htViewControl")
		        configuration.userContentController.addUserScript(WKUserScript(
		            source: \(scriptLiteral), injectionTime: \(startInjection ? ".atDocumentStart" : ".atDocumentEnd"), forMainFrameOnly: true))
		        let web = WKWebView(frame: .zero, configuration: configuration)
		        web.navigationDelegate = context.coordinator
		        return web
		    }
		    func updateNSView(_ web: WKWebView, context: Context) {
		        guard let file = model.documentURL, context.coordinator.file != file else { return }
		        context.coordinator.file = file
		        Task { @MainActor in
		            do {
		                let rules = try await WKContentRuleListStore.default().compileContentRuleList(
		                    forIdentifier: "HTViewOfflineControl", encodedContentRuleList:
		                    \(String(reflecting: badRules ? #"[{"trigger":{"url-filter":"^(https?|wss?|ftp|file):"},"action":{"type":"block"}}]"# : #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#)))
		                guard let rules else { throw NSError(domain: "NoRules", code: 1) }
		                web.configuration.userContentController.add(rules)
		                web.loadFileURL(file, allowingReadAccessTo: file)
		            } catch {
		                model.errorMessage = "Content rules: \\(error)"
		                \(badRules ? "if (error as NSError).domain == WKError.errorDomain && (error as NSError).code == WKError.Code.contentRuleListStoreCompileFailed.rawValue { recordHTViewControl(\"unsupported-regex:applied\") }" : "")
		            }
		        }
		    }
		    @MainActor final class Navigation: NSObject, WKNavigationDelegate {
		        let model: ApplicationModel
		        var file: URL?
		        init(model: ApplicationModel) { self.model = model }
		        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		            model.isLoading = false
		        }
		        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		            model.errorMessage = error.localizedDescription; model.isLoading = false
		        }
		        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		            model.errorMessage = error.localizedDescription; model.isLoading = false
		        }
		    }
		}
		public struct ApplicationRoot: View {
		    @ObservedObject var model: ApplicationModel
		    public init(model: ApplicationModel) {
		        self.model = model
		        let example = Bundle.module.url(forResource: "view-example", withExtension: "html", subdirectory: "Resources")!
		        precondition((try? String(contentsOf: example, encoding: .utf8)) == "view-resource-marker")
		    }
		    public var body: some View { EmbeddedWeb(model: model).frame(minWidth: 400, minHeight: 300) }
		}
		"""
}
