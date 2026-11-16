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

    func notifyStateChange(from previous: HotplateState?, to next: HotplateState, status: HotplateStatus?) {
        let center = UNUserNotificationCenter.current()
        let title: String
        let body: String
        switch (previous, next) {
        case (_, .idle):
            guard previous != nil else { return }
            title = "Firing stopped"
            body = status.map { profileText($0) } ?? "The hotplate has returned to idle."
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
            identifier: "hotplate.state.\(next.rawValue).\(UUID().uuidString)",
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
            identifier: "hotplate.safety.\(UUID().uuidString)",
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
            // 3× Submarine via the *alert* path: louder (alert volume) and
            // audible even with the ring/silent switch on silent.
            if submarineSound != 0 {
                playAlertChain(ids: [submarineSound, submarineSound, submarineSound])
            } else {
                AudioServicesPlayAlertSound(1057)
            }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.playAlertChain(ids: ids, index: index + 1)
            }
        }
    }

    enum FiringAlertKind { case completed, aborted }

    /// The bundled Submarine.aiff — created once, reused for every alert.
    private lazy var submarineSound: SystemSoundID = {
        guard let url = Bundle.main.url(forResource: "Submarine", withExtension: "aiff") else {
            return 0
        }
        var id: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(url as CFURL, &id)
        return id
    }()

    private func profileText(_ s: HotplateStatus) -> String {
        let name = s.profile ?? "Profile"
        let temp = Format.temp(s.temperature, units: "c")
        return "\(name) · \(temp)"
    }
}
