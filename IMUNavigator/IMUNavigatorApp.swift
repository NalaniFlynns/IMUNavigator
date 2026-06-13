import SwiftUI

@main
struct IMUNavigatorApp: App {
    @StateObject var engine = SensorFusionEngine()
    var body: some Scene { 
        WindowGroup { 
            MainView().environmentObject(engine).preferredColorScheme(.dark) 
        } 
    }
}
