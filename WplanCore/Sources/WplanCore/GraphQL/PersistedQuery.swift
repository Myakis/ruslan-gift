import Foundation

public struct PersistedQueryExtensions: Encodable {
    public struct Inner: Encodable {
        public let version: Int
        public let sha256Hash: String
    }
    public let persistedQuery: Inner

    public init(sha256Hash: String, version: Int = 1) {
        self.persistedQuery = Inner(version: version, sha256Hash: sha256Hash)
    }
}

/// Marker type for operations that take no variables (e.g. `StartOrFinishButtonState`).
public struct EmptyVariables: Encodable {}

public struct GraphQLOperation<Variables: Encodable> {
    public let operationName: String
    public let variables: Variables
    public let sha256Hash: String

    public init(operationName: String, variables: Variables, sha256Hash: String) {
        self.operationName = operationName
        self.variables = variables
        self.sha256Hash = sha256Hash
    }
}
