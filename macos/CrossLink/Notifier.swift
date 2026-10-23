import AppKit
import UserNotifications

/// Banners for what arrives from the phone. Clipboard content is not shown: it may be a password.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func textArrived(_ text: String) {
        post(title: "Текст с телефона", subtitle: "Нажмите, чтобы скопировать", body: String(text.prefix(200)), copy: text)
    }

    func clipboardArrived(characters: Int) {
        post(title: "Буфер обновлён с телефона", subtitle: nil, body: "\(characters) симв. — можно вставлять (⌘V)", copy: nil)
    }

    private func post(title: String, subtitle: String?, body: String, copy: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        if let copy { content.userInfo = ["copy": copy] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // A menu bar app counts as active, and banners of an active app are hidden unless asked for.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["copy"] as? String {
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        completionHandler()
    }
}
