// @frontmatter:start
// Defines self-contained HTView scenario HTML with deterministic inline color and load/click script states.
// @frontmatter:end

enum HTViewHTMLFixture {
	static let title: String = "HTView Offline HTML Fixture"
	static let scriptMarker: String = "htview-script-loaded"
	static let expectedColor: String = "rgb(17, 34, 51)"

	// The button changes script-status from scriptMarker to scriptMarker + "-clicked".
	// No base URL, server, remote resources, timers, or application implementation are needed.
	static let html: String = """
		<!doctype html>
		<html lang="en">
		<head>
		  <meta charset="utf-8">
		  <title>\(title)</title>
		  <style>
		    body { font-family: system-ui, sans-serif; margin: 24px; }
		    button { padding: 8px 12px; }
		  </style>
		</head>
		<body>
		  <h1>\(title)</h1>
		  <p id="inline-style" style="color: \(expectedColor);">Inline CSS is visible.</p>
		  <p id="script-status">script-pending</p>
		  <button id="script-button" type="button">Update script status</button>
		  <script>
		    document.addEventListener('DOMContentLoaded', () => {
		      const status = document.getElementById('script-status');
		      status.textContent = '\(scriptMarker)';
		      document.getElementById('script-button').addEventListener('click', () => {
		        status.textContent = '\(scriptMarker)-clicked';
		      });
		    });
		  </script>
		</body>
		</html>
		"""
}
