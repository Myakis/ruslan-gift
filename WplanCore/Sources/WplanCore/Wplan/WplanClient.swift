import Foundation

public final class WplanClient {
    public static let defaultBaseURL = URL(string: "https://wplan.office.lan/ru-RU/api/graphql")!

    private static let loginHash = "fb78036c7e60ac4e484699dc6c4ac71070ff22dbd5328207f22888ba7ff9e608"
    private static let buttonStateHash = "d8142718a7d030614362030016adf01cf85fb1950b9bd94fbd3d3dd6d27c8d38"
    private static let startOrFinishDayHash = "7809b05aa2dcb5ab05e21db5923aafb32a92cddfcaa56626593267775866e3f4"

    private let graphQL: GraphQLClient

    public init(baseURL: URL = WplanClient.defaultBaseURL, session: URLSession) {
        self.graphQL = GraphQLClient(baseURL: baseURL, session: session)
    }

    public func fetchButtonState() async throws -> WplanButtonState {
        let operation = GraphQLOperation(
            operationName: "StartOrFinishButtonState",
            variables: EmptyVariables(),
            sha256Hash: Self.buttonStateHash
        )
        let data: StartOrFinishButtonStateData = try await graphQL.execute(operation, method: .get, dataType: StartOrFinishButtonStateData.self)
        return data.startOrFinishDayButtonState
    }
}
