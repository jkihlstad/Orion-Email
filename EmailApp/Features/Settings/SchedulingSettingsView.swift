import SwiftUI

struct SchedulingSettingsView: View {
    private let api: ConvexCalendarAPI
    private let brainWorkerURL: URL
    private let clerkUserId: String

    init(api: ConvexCalendarAPI = ConvexCalendarAPI(
        baseURL: URL(string: "https://YOUR_CONVEX_HTTP_BASE")!,
        auth: ClerkSessionProvider()
    ), brainWorkerURL: URL = URL(string: "https://brain-calendar.YOUR_SUBDOMAIN.workers.dev")!,
         clerkUserId: String = "user_123") {
        self.api = api
        self.brainWorkerURL = brainWorkerURL
        self.clerkUserId = clerkUserId
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CalendarConnectionsView(
                            api: api,
                            brainWorkerURL: brainWorkerURL,
                            clerkUserId: clerkUserId
                        )
                    } label: {
                        Label("Calendar Connections", systemImage: "calendar.badge.plus")
                    }
                } header: {
                    Text("Integrations")
                }

                Section {
                    Text("Configure work hours here")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Work Hours")
                }

                Section {
                    Text("Configure meeting limits here")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Meeting Limits")
                }

                Section {
                    Text("Configure default policies here")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Defaults")
                }
            }
            .navigationTitle("Scheduling")
        }
    }
}
