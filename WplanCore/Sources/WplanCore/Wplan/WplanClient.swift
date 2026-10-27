import Foundation

public final class WplanClient {
    public static let defaultBaseURL = URL(string: "https://wplan.office.lan/ru-RU/api/graphql")!

    private let graphQL: GraphQLClient
    private let hashStore: PersistedQueryHashStore

    public init(
        baseURL: URL = WplanClient.defaultBaseURL,
        session: URLSession,
        hashStore: PersistedQueryHashStore = PersistedQueryHashStore(appGroupIdentifier: nil)
    ) {
        self.graphQL = GraphQLClient(baseURL: baseURL, session: session)
        self.hashStore = hashStore
    }

    public func fetchButtonState() async throws -> WplanButtonState {
        let operation = GraphQLOperation(
            operationName: PersistedQueryHashStore.Operation.buttonState.rawValue,
            variables: EmptyVariables(),
            sha256Hash: hashStore.hash(for: .buttonState)
        )
        let data: StartOrFinishButtonStateData = try await graphQL.execute(operation, method: .get, dataType: StartOrFinishButtonStateData.self)
        return data.startOrFinishDayButtonState
    }

    public func fetchWorkTimeEvents(for date: Date, calendar: Calendar = .current) async throws -> [WplanWorkTimeEvent] {
        let operation = GraphQLOperation(
            operationName: PersistedQueryHashStore.Operation.workTimeEvents.rawValue,
            variables: WorkTimeEventsVariables(date: WplanDateFormat.dayString(date, calendar: calendar)),
            sha256Hash: hashStore.hash(for: .workTimeEvents)
        )
        let data: WorkTimeEventsForDateData = try await graphQL.execute(operation, method: .get, dataType: WorkTimeEventsForDateData.self)
        return data.events(calendar: calendar)
    }

    public func login(username: String, password: String) async throws {
        let operation = GraphQLOperation(
            operationName: PersistedQueryHashStore.Operation.login.rawValue,
            variables: LoginVariables(username: username, password: password),
            sha256Hash: hashStore.hash(for: .login)
        )
        try await graphQL.executeIgnoringResult(operation, method: .post)
    }

    public func startOrFinishDay(isStart: Bool) async throws {
        let operation = GraphQLOperation(
            operationName: PersistedQueryHashStore.Operation.startOrFinishDay.rawValue,
            variables: StartOrFinishDayVariables(isStart: isStart),
            sha256Hash: hashStore.hash(for: .startOrFinishDay)
        )
        try await graphQL.executeIgnoringResult(operation, method: .post)
    }
}
