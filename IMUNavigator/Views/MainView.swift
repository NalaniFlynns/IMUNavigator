import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "location.north.line.fill") }
            HistoryView()
                .tabItem { Label("Storage", systemImage: "folder.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
