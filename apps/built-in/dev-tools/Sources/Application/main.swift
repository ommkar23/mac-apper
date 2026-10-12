// @frontmatter:start
// Starts the DevTools XPC service with generated routing and application-owned controllers.
// @frontmatter:end
import Foundation

let factory = ControllerFactory(
	projectsRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-apper")
)
OpenXPCGeneratedService.listen(controllers: factory.controllers())
