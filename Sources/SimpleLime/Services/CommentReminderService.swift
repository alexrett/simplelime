import Foundation
import UserNotifications

extension Notification.Name {
    static let simpleLimeOpenComment = Notification.Name("SimpleLimeOpenComment")
}

protocol CommentReminderScheduling: AnyObject {
    func scheduleReminder(for comment: DocumentComment)
    func cancelReminder(commentID: UUID)
}

final class CommentReminderService: NSObject, CommentReminderScheduling, UNUserNotificationCenterDelegate {
    static let shared = CommentReminderService()

    private let center: UNUserNotificationCenter
    private let notificationPrefix = "simplelime.comment."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func activate() {
        center.delegate = self
    }

    func scheduleReminder(for comment: DocumentComment) {
        guard let reminderAt = comment.reminderAt else {
            cancelReminder(commentID: comment.id)
            return
        }

        let interval = max(1, reminderAt.timeIntervalSinceNow)
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard let self, granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "SimpleLime comment"
            content.body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? comment.displayQuote
                : comment.body
            content.sound = .default
            content.userInfo = [
                "commentID": comment.id.uuidString,
                "documentKey": comment.documentKey
            ]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: self.notificationIdentifier(for: comment.id),
                content: content,
                trigger: trigger
            )

            self.center.removePendingNotificationRequests(withIdentifiers: [self.notificationIdentifier(for: comment.id)])
            self.center.add(request)
        }
    }

    func cancelReminder(commentID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: commentID)])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier(for: commentID)])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let rawID = response.notification.request.content.userInfo["commentID"] as? String,
              let commentID = UUID(uuidString: rawID) else {
            return
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .simpleLimeOpenComment,
                object: nil,
                userInfo: ["commentID": commentID]
            )
        }
    }

    private func notificationIdentifier(for commentID: UUID) -> String {
        "\(notificationPrefix)\(commentID.uuidString)"
    }
}
