import SwiftUI
import MessageUI
import UIKit

/// Where support email is sent and how the message is seeded. Centralized so the Settings
/// "Contact Support" row (and any future entry point) share one recipient, subject, and body.
enum SupportContact {
    static let recipient = "hello@babybuddy.app"
    static let subject = String(localized: "Baby Buddy Support")

    /// The device/app details we offer to attach so we can reproduce issues. Kept human-readable
    /// (not JSON) so the customer can see exactly what they're sending and edit or delete it.
    static var diagnostics: String {
        String(localized: """
        \(Self.diagnosticsHeader)
        Device: \(deviceModel)
        System: \(systemVersion)
        App: Baby Buddy \(appVersion)
        """)
    }

    /// Marker line the diagnostics block starts with, so the intent is obvious in the composer.
    static let diagnosticsHeader = String(localized: "— Diagnostics (helps us investigate; delete if you prefer) —")

    /// The seeded email body. When `includeDiagnostics` is true the block is appended below a
    /// blank space the customer types their message into.
    static func body(includeDiagnostics: Bool) -> String {
        let intro = String(localized: "Hi Baby Buddy team,\n\n\n")
        return includeDiagnostics ? intro + diagnostics + "\n" : intro
    }

    /// A `mailto:` URL used as the fallback when the in-app composer isn't available (no Mail
    /// account configured), so the button still does something useful.
    static func mailtoURL(includeDiagnostics: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(includeDiagnostics: includeDiagnostics)),
        ]
        return components.url
    }

    // MARK: Diagnostics fields

    /// The hardware model identifier (e.g. `iPhone16,2`). On the simulator, the simulated device.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    // MARK: Feedback account deletion

    /// Send Feedback ▸ Delete Feedback Account mails this request, which the owner fulfills with
    /// Users ▸ Remove from portal in Quackback's admin. Quackback 0.14.1 has no self-service deletion
    /// (kguydev/feedback-stack#18), and its messenger is reachable only through internal server
    /// functions, so the request goes by Mail rather than the support chat.
    static let deletionSubject = String(localized: "Delete my feedback account")

    /// The request and the app version, nothing else from the device. The feedback account's
    /// email goes in too: the person may write from a different address.
    static func deletionBody(feedbackEmail: String?) -> String {
        var lines = [String(localized: "Please delete my feedback account. (Sent from Baby Buddy Companion's Delete Feedback Account button.)"), ""]
        if let feedbackEmail { lines.append(String(localized: "Feedback account: \(feedbackEmail)")) }
        lines.append(String(localized: "App: Baby Buddy \(appVersion)"))
        return lines.joined(separator: "\n")
    }
}

/// SwiftUI wrapper around `MFMailComposeViewController` so the Settings screen can present the
/// system in-app mail composer as a sheet. `onFinish` fires for send, cancel, save and error
/// alike, with the result for a caller that needs to know whether it was sent.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result)
        }
    }
}
