import Foundation
import UserNotifications
import Astrology

/// Schedules local notifications for an upcoming retrograde and the soonest exact
/// transits. Best-effort: requests permission, then replaces any pending alerts.
enum TransitNotifications {

    /// Request authorization and (re)schedule alerts. Returns whether granted.
    @discardableResult
    static func schedule(retrograde: RetrogradePeriod?, events: [ForecastEvent],
                         chartName: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        center.removeAllPendingNotificationRequests()
        var requests: [UNNotificationRequest] = []

        if let r = retrograde, r.start > Date() {
            requests.append(request(
                id: "mercury-retrograde",
                title: "Mercury stations retrograde",
                body: "Retrograde through \(r.end.formatted(date: .abbreviated, time: .omitted)).",
                date: r.start))
        }
        for e in events.prefix(5) where e.date > Date() {
            requests.append(request(
                id: e.id,
                title: "\(e.transiting.name) \(e.kind.name.lowercased()) \(e.natal.name)",
                body: "Exact today in \(chartName).",
                date: e.date))
        }
        for req in requests { try? await center.add(req) }
        return true
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// A notification fired at 9am local on the event's day.
    private static func request(id: String, title: String, body: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
