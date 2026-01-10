import SwiftUI

@main
struct CalendarAppApp: App {
    private let auth = ClerkSessionProvider(devUserId: "user_123", role: "user")
    private let api: ConvexCalendarAPI

    init() {
        api = ConvexCalendarAPI(
            baseURL: URL(string: "https://YOUR_CONVEX_HTTP_BASE")!,
            auth: auth
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ProposalsListView(api: api)
                    .tabItem { Label("Proposals", systemImage: "sparkles") }

                SchedulingSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
