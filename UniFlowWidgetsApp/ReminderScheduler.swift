import Foundation
import UserNotifications

@MainActor
enum ReminderScheduler {
    static let prefix = "uniflow.visit."

    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func refresh(workspace: UniFlowWorkspace, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let all = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: all.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard let until = Calendar.current.date(byAdding: .day, value: 45, to: now) else { return }
        let next = CalendarEngine.occurrences(workspace, between: now, and: until)
            .filter { $0.start.addingTimeInterval(-1800) > now }.prefix(50)
        for occ in next {
            let event = UNMutableNotificationContent()
            event.title = "In 30 Minuten: \(occ.title)"
            event.subtitle = occ.category
            event.body = [occ.organizer, occ.location].filter { !$0.isEmpty }.joined(separator: " · ")
            event.sound = .default
            let reminderDate = occ.start.addingTimeInterval(-1800)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + occ.id, content: event, trigger: trigger))
        }
    }

    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let all = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: all.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }
}
