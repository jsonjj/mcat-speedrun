// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Bottom-tab navigation shell. Each tab is its own NavigationStack so study
// screens push on top of the relevant tab.

import SwiftUI

struct RootView: View {
    // Initial tab can be set via the MCAT_TAB launch env var (used for QA screenshots).
    @State private var selection = Int(ProcessInfo.processInfo.environment["MCAT_TAB"] ?? "0") ?? 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tag(0)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            NavigationStack { RoadmapView() }
                .tag(1)
                .tabItem { Label("Today's Path", systemImage: "map.fill") }
            NavigationStack { ExtraPracticeView() }
                .tag(2)
                .tabItem { Label("Practice", systemImage: "bolt.fill") }
            NavigationStack { AccountView() }
                .tag(3)
                .tabItem { Label("Account", systemImage: "person.fill") }
        }
        .tint(Theme.accent)
    }
}
