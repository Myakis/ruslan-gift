import Foundation

public final class GraphQLClient {
    public enum GraphQLHTTPMethod { case get, post }

    public enum ClientError: Error, Equatable {
        case invalidResponse
        case http(status: Int, body: String)
        case graphQL(messages: [String])
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func execute<Variables: Encodable, ResponseData: Decodable>(
        _ operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod,
        dataType: ResponseData.Type
    ) async throws -> ResponseData {
        let body = try await performRequest(for: operation, method: method)
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<ResponseData>.self, from: body)
        if let errors = envelope.errors, !errors.isEmpty {
            throw ClientError.graphQL(messages: errors.map(\.message))
        }
        guard let data = envelope.data else { throw ClientError.invalidResponse }
        return data
    }

    public func executeIgnoringResult<Variables: Encodable>(
        _ operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) async throws {
        let body = try await performRequest(for: operation, method: method)
        let envelope = try JSONDecoder().decode(ErrorsOnlyEnvelope.self, from: body)
        if let errors = envelope.errors, !errors.isEmpty {
            throw ClientError.graphQL(messages: errors.map(\.message))
        }
    }

    private func performRequest<Variables: Encodable>(
        for operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) async throws -> Data {
        let request = try makeRequest(for: operation, method: method)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func makeRequest<Variables: Encodable>(
        for operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) throws -> URLRequest {
        let extensions = PersistedQueryExtensions(sha256Hash: operation.sha256Hash)
        switch method {
        case .post:
            var request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("undefined", forHTTPHeaderField: "x-xsrf-token")
            let body = GraphQLRequestBody(operationName: operation.operationName, variables: operation.variables, extensions: extensions)
            request.httpBody = try JSONEncoder().encode(body)
            return request
        case .get:
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw ClientError.invalidResponse
            }
            let variablesJSON = String(data: try JSONEncoder().encode(operation.variables), encoding: .utf8) ?? "{}"
            let extensionsJSON = String(data: try JSONEncoder().encode(extensions), encoding: .utf8) ?? "{}"
            components.queryItems = [
                URLQueryItem(name: "operationName", value: operation.operationName),
                URLQueryItem(name: "variables", value: variablesJSON),
                URLQueryItem(name: "extensions", value: extensionsJSON)
            ]
            guard let url = components.url else { throw ClientError.invalidResponse }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("undefined", forHTTPHeaderField: "x-xsrf-token")
            return request
        }
    }
}

private struct ErrorsOnlyEnvelope: Decodable {
    let errors: [GraphQLErrorMessage]?
}

private struct GraphQLRequestBody<Variables: Encodable>: Encodable {
    let operationName: String
    let variables: Variables
    let extensions: PersistedQueryExtensions
}

struct GraphQLEnvelope<ResponseData: Decodable>: Decodable {
    let data: ResponseData?
    let errors: [GraphQLErrorMessage]?
}

public struct GraphQLErrorMessage: Decodable, Equatable {
    public let message: String
}
