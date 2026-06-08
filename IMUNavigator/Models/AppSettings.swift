import SwiftUI
import Combine

enum RecordingMode: String, Codable, CaseIterable, Identifiable { case time = "Time"; case distance = "Distance"; var id: String { self.rawValue } }
enum StorageFormat: String, Codable, CaseIterable, Identifiable { case json = "JSON"; case sqlite = "SQLite"; var id: String { self.rawValue } }
enum SLAMFilterMode: String, Codable, CaseIterable, Identifiable { case strict = "Strict"; case moderate = "Moderate"; case off = "Off"; var id: String { self.rawValue } }
enum CoreNavMode: String, Codable, CaseIterable, Identifiable { case fusion = "Cascade Fusion (VIO->PDR->NR)"; case pureIMU = "Blind Mode (PDR->NR)"; var id: String { self.rawValue } }
enum ErrorChartMode: String, Codable, CaseIterable, Identifiable { case cumulative = "Cumulative"; case instantaneous = "Instantaneous"; var id: String { self.rawValue } }

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var triggerUpdate: Bool = false
    @Published var hasDoneRuntimeCalibration: Bool = false
    
    @AppStorage("coreNavMode") var coreNavMode: CoreNavMode = .fusion
    @AppStorage("recordingMode") var recordingMode: RecordingMode = .time
    @AppStorage("storageFormat") var storageFormat: StorageFormat = .sqlite
    @AppStorage("enableBackgroundRecording") var enableBackgroundRecording: Bool = true
    
    @AppStorage("recordIntervalTime") var recordIntervalTime: Double = 0.0
    @AppStorage("recordIntervalSpace") var recordIntervalSpace: Double = 0.0
    @AppStorage("slamFilterMode") var slamFilterMode: SLAMFilterMode = .strict
    @AppStorage("enableSLAMCorrection") var enableSLAMCorrection: Bool = true
    
    @AppStorage("showAltitudeChart") var showAltitudeChart: Bool = true
    @AppStorage("showErrorChart") var showErrorChart: Bool = true
    @AppStorage("errorChartMode") var errorChartMode: ErrorChartMode = .cumulative
    @AppStorage("showResidualChart") var showResidualChart: Bool = true
    
    @AppStorage("enableZUPT") var enableZUPT: Bool = true
    @AppStorage("zuptThreshold") var zuptThreshold: Double = 0.05
    @AppStorage("zuptGyroThreshold") var zuptGyroThreshold: Double = 0.1
    
    @AppStorage("dampingX") var dampingX: Double = 0.5
    @AppStorage("dampingY") var dampingY: Double = 0.5
    @AppStorage("driftCompX") var driftCompX: Double = 0.0
    @AppStorage("driftCompY") var driftCompY: Double = 0.0
    
    @AppStorage("enableDynamicCalibration") var enableDynamicCalibration: Bool = false
    @AppStorage("autoRotateCanvas") var autoRotateCanvas: Bool = true
    
    @AppStorage("recordGNSS") var recordGNSS: Bool = true
    @AppStorage("recordBarometer") var recordBarometer: Bool = true
    @AppStorage("recordAcceleration") var recordAcceleration: Bool = true
    
    @AppStorage("manualBiasX") var manualBiasX: Double = 0.0
    @AppStorage("manualBiasY") var manualBiasY: Double = 0.0
    @AppStorage("manualBiasZ") var manualBiasZ: Double = 0.0
    
    @AppStorage("enableAutoAlignment") var enableAutoAlignment: Bool = true
    @AppStorage("imuYawOffset") var imuYawOffset: Double = 0.0
    @AppStorage("imuMirrorX") var imuMirrorX: Bool = false
    @AppStorage("imuMirrorY") var imuMirrorY: Bool = false
}
