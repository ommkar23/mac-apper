// @frontmatter:start
// Performs bounded ephemeral HTTPS requests with a total timeout and rejects redirects so credentials cannot be forwarded to another host.
// @frontmatter:end
import Foundation

public struct HTTPReply: Sendable {
	public let status: Int
	public let data: Data
	public init(status: Int, data: Data) { self.status = status; self.data = data }
}

public protocol HTTPTransport: Sendable {
	func send(_ request: URLRequest) async throws -> HTTPReply
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
	func urlSession(
		_ session: URLSession, task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
	) {
		completionHandler(nil)
	}
}

public final class LiveTransport: HTTPTransport, @unchecked Sendable {
	private let session: URLSession
	public init() {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 90
		configuration.timeoutIntervalForResource = 90
		configuration.urlCache = nil
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
	}
	deinit { session.invalidateAndCancel() }

	public func send(_ request: URLRequest) async throws -> HTTPReply {
		let (bytes, response) = try await session.bytes(for: request)
		guard
			let response = response as? HTTPURLResponse
		else { throw VisionFailure(.network_error, "Google did not return an HTTP response.") }
		var data = Data()
		for try await byte in bytes {
			guard
				data.count < 1_048_576
			else { throw VisionFailure(.invalid_response, "Google response exceeded the 1 MiB limit.") }
			data.append(byte)
		}
		return HTTPReply(status: response.statusCode, data: data)
	}
}
