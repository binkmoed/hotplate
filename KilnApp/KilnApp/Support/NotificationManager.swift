import Foundation
import UserNotifications
import UIKit
import AudioToolbox

/// Wraps `UNUserNotificationCenter` for safety/completion alerts. No-op until authorized.
final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyStateChange(from previous: KilnState?, to next: KilnState, status: KilnStatus?) {
        let center = UNUserNotificationCenter.current()
        let title: String
        let body: String
        switch (previous, next) {
        case (_, .idle):
            guard previous != nil else { return }
            title = "Firing stopped"
            body = status.map { profileText($0) } ?? "The kiln has returned to idle."
        case (_, .running) where previous == .paused:
            title = "Firing resumed"
            body = status.map { profileText($0) } ?? "Profile is running again."
        case (.running, .paused):
            title = "Firing paused"
            body = status.map { profileText($0) } ?? "The profile has been paused."
        case (_, .running):
            // Started fresh — only notify if this wasn't the first status we ever saw.
            guard previous != nil else { return }
            title = "Firing started"
            body = status.map { profileText($0) } ?? "A profile is now running."
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "kiln.state.\(next.rawValue).\(UUID().uuidString)",
            content: content, trigger: nil
        )
        center.add(req)
    }

    /// Fire-and-forget safety alert (e.g. over-temperature).
    func notifySafety(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        let req = UNNotificationRequest(
            identifier: "kiln.safety.\(UUID().uuidString)",
            content: content, trigger: nil
        )
        center.add(req)
    }

    // MARK: - In-app haptics + sound

    /// Haptic buzz + audible ping for the in-app completion/abort alerts
    /// (SwiftUI alerts are silent; the notification banner only shows when
    /// the app is backgrounded).
    func hapticAndSound(kind: FiringAlertKind) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        switch kind {
        case .completed:
            generator.notificationOccurred(.success)
            // 3× timer ping via the *alert* path: louder (alert volume) and
            // audible even with the ring/silent switch on silent.
            playAlertChain(ids: [1057, 1057, 1057])
        case .aborted:
            generator.notificationOccurred(.error)
            AudioServicesPlayAlertSound(1053)   // low error tone
        }
    }

    /// Play system alert sounds one after another (~1s apart is built into
    /// each sound's natural length; gaps keep them from blending together).
    private func playAlertChain(ids: [SystemSoundID], index: Int = 0) {
        guard index < ids.count else { return }
        AudioServicesPlayAlertSoundWithCompletion(ids[index]) { [weak self] in
            self?.playAlertChain(ids: ids, index: index + 1)
        }
    }

    enum FiringAlertKind { case completed, aborted }

    private func profileText(_ s: KilnStatus) -> String {
        let name = s.profile ?? "Profile"
        let temp = Format.temp(s.temperature, units: "c")
        return "\(name) · \(temp)"
    }
}
