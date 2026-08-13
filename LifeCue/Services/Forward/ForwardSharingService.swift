import Foundation
import UIKit
import SwiftUI

/// Outgoing Forward only — presents text via the system share sheet.
/// Not a Share Extension; LifeCue does not receive shared content.
@MainActor
protocol ForwardSharingServing: AnyObject {
    func present(text: String) async
}

@MainActor
final class FakeForwardSharingService: ForwardSharingServing {
    private(set) var presentedTexts: [String] = []

    func present(text: String) async {
        presentedTexts.append(text)
    }

    func reset() {
        presentedTexts.removeAll()
    }
}

/// Presents `UIActivityViewController` with the forwarded plain text.
@MainActor
final class SystemForwardSharingService: ForwardSharingServing {
    func present(text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let activity = UIActivityViewController(
                activityItems: [text],
                applicationActivities: nil
            )
            guard let presenter = Self.topViewController() else {
                continuation.resume()
                return
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            activity.completionWithItemsHandler = { _, _, _, _ in
                continuation.resume()
            }
            presenter.present(activity, animated: true)
        }
    }

    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
