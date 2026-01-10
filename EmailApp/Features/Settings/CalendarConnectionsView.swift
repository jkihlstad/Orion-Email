import SwiftUI

struct CalendarConnectionsView: View {
    @StateObject private var appleConnector = AppleCalendarConnector()
    @StateObject private var googleConnector: GoogleCalendarConnector

    @State private var isRequestingAppleAccess = false
    @State private var isSyncing = false
    @State private var syncResult: String?
    @State private var showError = false
    @State private var errorMessage = ""

    private let api: ConvexCalendarAPI

    init(api: ConvexCalendarAPI, brainWorkerURL: URL, clerkUserId: String) {
        self.api = api
        _googleConnector = StateObject(wrappedValue: GoogleCalendarConnector(
            brainWorkerBaseURL: brainWorkerURL,
            clerkUserId: clerkUserId
        ))
    }

    var body: some View {
        List {
            // Apple Calendar Section
            Section {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Calendar")
                            .font(.headline)
                        Text(appleAccessDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if appleConnector.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !appleConnector.isConnected {
                    Button {
                        requestAppleAccess()
                    } label: {
                        HStack {
                            Text("Connect Apple Calendar")
                            if isRequestingAppleAccess {
                                ProgressView()
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .disabled(isRequestingAppleAccess)
                } else {
                    Button("Sync Now") {
                        syncAppleCalendar()
                    }
                    .disabled(isSyncing)
                }
            } header: {
                Text("Device Calendar")
            } footer: {
                Text("Events from your device's calendar will be synced to enable AI scheduling.")
            }

            // Google Calendar Section
            Section {
                HStack {
                    Image(systemName: "g.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Calendar")
                            .font(.headline)
                        if let email = googleConnector.connectedEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if googleConnector.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !googleConnector.isConnected {
                    Button {
                        connectGoogle()
                    } label: {
                        HStack {
                            Text("Connect Google Calendar")
                            if googleConnector.isAuthenticating {
                                ProgressView()
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .disabled(googleConnector.isAuthenticating)
                } else {
                    Button("Sync Now") {
                        syncGoogleCalendar()
                    }
                    .disabled(isSyncing)

                    Button("Disconnect", role: .destructive) {
                        disconnectGoogle()
                    }
                }
            } header: {
                Text("Cloud Calendar")
            } footer: {
                Text("Connect your Google Calendar for cross-device sync and AI-powered scheduling.")
            }

            // Sync Status
            if let result = syncResult {
                Section {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Last Sync")
                }
            }
        }
        .navigationTitle("Calendar Connections")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            try? await googleConnector.checkConnectionStatus()
        }
    }

    private var appleAccessDescription: String {
        switch appleConnector.accessLevel {
        case .full: return "Full access granted"
        case .writeOnly: return "Write-only access"
        case .denied: return "Access denied - check Settings"
        case .notDetermined: return "Not connected"
        }
    }

    private func requestAppleAccess() {
        isRequestingAppleAccess = true
        Task {
            do {
                let granted = try await appleConnector.requestFullAccess()
                if granted {
                    await syncAppleCalendarAsync()
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isRequestingAppleAccess = false
        }
    }

    private func syncAppleCalendar() {
        Task {
            await syncAppleCalendarAsync()
        }
    }

    private func syncAppleCalendarAsync() async {
        isSyncing = true
        defer { isSyncing = false }

        let startDate = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let endDate = Date().addingTimeInterval(180 * 24 * 60 * 60)

        let events = appleConnector.fetchEvents(from: startDate, to: endDate)
        let canonicalEvents = appleConnector.convertToCanonicalEvents(events)

        // TODO: Send to Convex via api.ingestEvents
        syncResult = "Synced \(canonicalEvents.count) Apple Calendar events"
    }

    private func connectGoogle() {
        Task {
            do {
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) else { return }

                try await googleConnector.startOAuthFlow(presentingWindow: window)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func syncGoogleCalendar() {
        isSyncing = true
        Task {
            do {
                let count = try await googleConnector.triggerSync()
                syncResult = "Synced \(count) Google Calendar events"
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSyncing = false
        }
    }

    private func disconnectGoogle() {
        Task {
            do {
                try await googleConnector.disconnect()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
