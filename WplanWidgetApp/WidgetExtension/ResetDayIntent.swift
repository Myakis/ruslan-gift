import AppIntents
import WidgetKit
import WplanCore

/// Runs inside the widget extension process, which has no access to the host
/// app's live `AutoclickScheduler` actor — it can only leave a request in the
/// shared App Group container (`WidgetResetRequestStore`) and update the local
/// snapshot optimistically so the widget looks reset immediately. The host app's
/// own poll loop (`AutomationController.applyPendingResetRequestIfAny`) is what
/// actually clears `DayState.autoStartSuppressedToday`.
struct ResetDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Сбросить завершённый день"
    static var description = IntentDescription("Позволяет автоматике снова начать рабочий день сегодня.")

    private let appGroupIdentifier = "group.ru.itmo.wplanwidget"

    func perform() async throws -> some IntentResult {
        WidgetResetRequestStore.requestReset(appGroupIdentifier: appGroupIdentifier)
        if let current = WidgetSnapshotStore.load(appGroupIdentifier: appGroupIdentifier) {
            WidgetSnapshotStore.save(
                WidgetSnapshot(
                    isStart: true,
                    vpnStatus: current.vpnStatus,
                    startedAt: nil,
                    scheduledFinishAt: nil,
                    finishedAt: nil,
                    updatedAt: Date()
                ),
                appGroupIdentifier: appGroupIdentifier
            )
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "WplanRingWidget")
        return .result()
    }
}
