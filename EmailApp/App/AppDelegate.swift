// AppDelegate.swift
// EmailApp - AppDelegate for push notification handling
//
// Integrates SharedKit PushNotificationManager for unified notification handling

import UIKit
import SharedKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Push Notification Manager
    private let pushManager = PushNotificationManager.shared

    // MARK: - App Lifecycle
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up push notification handling
        setupPushNotifications()

        return true
    }

    // MARK: - Push Notification Setup
    private func setupPushNotifications() {
        // Set up PushNotificationManager as the delegate
        pushManager.applicationDidFinishLaunching()

        // Register notification handler for this app
        pushManager.registerHandler(EmailNotificationHandler(), for: Bundle.main.bundleIdentifier ?? "")

        // Configure backend URL and JWT provider
        if let backendURL = URL(string: "https://api.orion.app") {
            pushManager.configure(backendURL: backendURL) {
                // Get JWT from Clerk session
                try await ClerkSessionProvider.shared.getToken()
            }
        }

        // Request authorization and register for remote notifications
        Task {
            do {
                let authorized = try await pushManager.setup(with: [.alert, .sound, .badge])
                if authorized {
                    print("[EmailApp] Push notifications authorized and registered")
                }
            } catch {
                print("[EmailApp] Failed to set up push notifications: \(error)")
            }
        }
    }

    // MARK: - Push Notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await pushManager.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushManager.didFailToRegisterForRemoteNotifications(withError: error)
        print("[EmailApp] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        pushManager.processRemoteNotification(userInfo, completionHandler: completionHandler)
    }
}

// MARK: - Email Notification Handler

/// Handles push notifications specific to the email app
final class EmailNotificationHandler: PushNotificationHandler, @unchecked Sendable {

    func handleNotification(payload: [AnyHashable: Any]) async {
        // Handle incoming notification while app is in foreground
        print("[EmailNotificationHandler] Received notification: \(payload)")

        // Check notification type and handle accordingly
        if let type = payload["type"] as? String {
            switch type {
            case "new_email":
                // Notify the app to refresh email list
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .emailNewMessageReceived,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "calendar_invite":
                // Handle calendar invitation
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .emailCalendarInviteReceived,
                        object: nil,
                        userInfo: payload
                    )
                }
            case "proposal_ready":
                // AI proposal is ready
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .emailProposalReady,
                        object: nil,
                        userInfo: payload
                    )
                }
            default:
                break
            }
        }
    }

    func handleNotificationTap(payload: [AnyHashable: Any], action: String?) async {
        // Handle user tapping on notification
        print("[EmailNotificationHandler] Notification tapped with action: \(action ?? "default")")

        await MainActor.run {
            // Handle different actions
            if let action = action {
                switch action {
                case OrionNotificationAction.reply.rawValue:
                    // Open compose view with reply
                    if let threadId = payload["threadId"] as? String {
                        NotificationCenter.default.post(
                            name: .emailOpenReply,
                            object: nil,
                            userInfo: ["threadId": threadId, "replyText": payload["replyText"] as? String ?? ""]
                        )
                    }
                case OrionNotificationAction.archive.rawValue:
                    // Archive the email
                    if let threadId = payload["threadId"] as? String {
                        NotificationCenter.default.post(
                            name: .emailArchiveThread,
                            object: nil,
                            userInfo: ["threadId": threadId]
                        )
                    }
                case OrionNotificationAction.view.rawValue:
                    // Open the email thread
                    if let threadId = payload["threadId"] as? String {
                        NotificationCenter.default.post(
                            name: .emailOpenThread,
                            object: nil,
                            userInfo: ["threadId": threadId]
                        )
                    }
                default:
                    break
                }
            } else {
                // Default tap - open the email thread
                if let threadId = payload["threadId"] as? String {
                    NotificationCenter.default.post(
                        name: .emailOpenThread,
                        object: nil,
                        userInfo: ["threadId": threadId]
                    )
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let emailNewMessageReceived = Notification.Name("emailNewMessageReceived")
    static let emailCalendarInviteReceived = Notification.Name("emailCalendarInviteReceived")
    static let emailProposalReady = Notification.Name("emailProposalReady")
    static let emailOpenReply = Notification.Name("emailOpenReply")
    static let emailArchiveThread = Notification.Name("emailArchiveThread")
    static let emailOpenThread = Notification.Name("emailOpenThread")
}
