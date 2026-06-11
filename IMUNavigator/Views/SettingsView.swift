import SwiftUI
import UIKit

extension View {
    func endTextEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    
    var body: some View {
        SettingsFormContent(engine: engine).equatable()
    }
}

struct SettingsFormContent: View, Equatable {
    var engine: SensorFusionEngine
    
    static func == (lhs: SettingsFormContent, rhs: SettingsFormContent) -> Bool {
        return true 
    }
    
    @State private var showCalibration = false
    @State private var showAlignment = false
    @FocusState private var isInputActive: Bool
    
    @State private var localNavMode: CoreNavMode = AppSettings.shared.coreNavMode
    @State private var dampingX: Double = AppSettings.shared.dampingX
    @State private var dampingY: Double = AppSettings.shared.dampingY
    @State private var enableSLAM: Bool = AppSettings.shared.enableSLAMCorrection
    @State private var enableDynamicCalib: Bool = AppSettings.shared.enableDynamicCalibration
    @State private var recordingMode: RecordingMode = AppSettings.shared.recordingMode
    @State private var showAltitudeChart: Bool = AppSettings.shared.showAltitudeChart
    @State private var showErrorChart: Bool = AppSettings.shared.showErrorChart
    @State private var errorChartMode: ErrorChartMode = AppSettings.shared.errorChartMode
    @State private var showResidualChart: Bool = AppSettings.shared.showResidualChart
    @State private var storageFormat: StorageFormat = AppSettings.shared.storageFormat
    @State private var enableBackgroundRecord: Bool = AppSettings.shared.enableBackgroundRecording
    @State private var slamFilterMode: SLAMFilterMode = AppSettings.shared.slamFilterMode
    @State private var enableZUPT: Bool = AppSettings.shared.enableZUPT
    @State private var autoRotateCanvas: Bool = AppSettings.shared.autoRotateCanvas
    @State private var recordGNSS: Bool = AppSettings.shared.recordGNSS
    @State private var recordBarometer: Bool = AppSettings.shared.recordBarometer
    @State private var recordAcceleration: Bool = AppSettings.shared.recordAcceleration
    
    @State private var timeStr: String = ""
    @State private var spaceStr: String = ""
    @State private var biasXStr: String = ""
    @State private var biasYStr: String = ""
    @State private var biasZStr: String = ""
    @State private var driftXStr: String = ""
    @State private var driftYStr: String = ""
    @State private var zuptAccStr: String = ""
    @State private var zuptGyroStr: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Core Routing Engine")) {
                    VStack(alignment: .leading, spacing: 5) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            UIKitSegmentedPicker(
                                selection: Binding(
                                    get: { Array(CoreNavMode.allCases).firstIndex(of: localNavMode) ?? 0 },
                                    set: { newIndex in
                                        let selectedMode = Array(CoreNavMode.allCases)[newIndex]
                                        localNavMode = selectedMode
                                        AppSettings.shared.coreNavMode = selectedMode
                                        engine.switchNavMode(to: selectedMode)
                                    }
                                ),
                                items: CoreNavMode.allCases.map { $0.rawValue }
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    Button("Static Bias Calibration") { showCalibration = true }.foregroundColor(.blue)
                    Button("Spatial Alignment Lab") { showAlignment = true }.foregroundColor(.orange)
                    
                    NavigationLink(destination: DebugPanelView().environmentObject(engine)) {
                        HStack { Image(systemName: "terminal.fill"); Text("System Debug Console") }
                    }.foregroundColor(.purple)
                    
                    HStack { Text("Bias X"); Spacer(); TextField("X", text: $biasXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasXStr) { if let d = Double($0) { AppSettings.shared.manualBiasX = d } } }
                    HStack { Text("Bias Y"); Spacer(); TextField("Y", text: $biasYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasYStr) { if let d = Double($0) { AppSettings.shared.manualBiasY = d } } }
                    HStack { Text("Bias Z"); Spacer(); TextField("Z", text: $biasZStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasZStr) { if let d = Double($0) { AppSettings.shared.manualBiasZ = d } } }
                    
                    Toggle("Enable SLAM Position Correction", isOn: $enableSLAM)
                        .onChange(of: enableSLAM) { AppSettings.shared.enableSLAMCorrection = $0 }
                    Toggle("Enable Dynamic Calibration (VIO)", isOn: $enableDynamicCalib)
                        .onChange(of: enableDynamicCalib) { AppSettings.shared.enableDynamicCalibration = $0 }
                }
                
                Section(header: Text("Drift Compensation & Damping")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("X-Axis Damping: \(String(format: "%.2f", dampingX))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingX, range: 0.0...1.0)
                            .onChange(of: dampingX) { AppSettings.shared.dampingX = $0 }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Y-Axis Damping: \(String(format: "%.2f", dampingY))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingY, range: 0.0...1.0)
                            .onChange(of: dampingY) { AppSettings.shared.dampingY = $0 }
                    }
                    
                    HStack {
                        Label("Global X Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("X", text: $driftXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftXStr) { if let d = Double($0) { AppSettings.shared.driftCompX = d } }
                    }
                    HStack {
                        Label("Global Y Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("Y", text: $driftYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftYStr) { if let d = Double($0) { AppSettings.shared.driftCompY = d } }
                    }
                }
                
                Section(header: Text("Recording Mode")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        UIKitSegmentedPicker(
                            selection: Binding(
                                get: { recordingMode == .time ? 0 : 1 },
                                set: { recordingMode = $0 == 0 ? .time : .distance }
                            ),
                            items: ["By Time", "By Distance"]
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: recordingMode) { AppSettings.shared.recordingMode = $0 }
                    
                    if recordingMode == .time {
                        HStack { Label("Time Interval (s)", systemImage: "clock"); Spacer(); TextField("0 = No limit", text: $timeStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: timeStr) { if let d = Double($0) { AppSettings.shared.recordIntervalTime = d } } }
                    } else {
                        HStack { Label("Space Interval (m)", systemImage: "ruler.fill"); Spacer(); TextField("0 = No limit", text: $spaceStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: spaceStr) { if let d = Double($0) { AppSettings.shared.recordIntervalSpace = d } } }
                    }
                }
                
                Section(header: Text("Charts Display")) {
                    Toggle("Show Altitude Chart", isOn: $showAltitudeChart)
                        .onChange(of: showAltitudeChart) { AppSettings.shared.showAltitudeChart = $0 }
                    Toggle("Show Error Chart", isOn: $showErrorChart)
                        .onChange(of: showErrorChart) { AppSettings.shared.showErrorChart = $0 }
                    if showErrorChart {
                        ScrollView(.horizontal, showsIndicators: false) {
                            UIKitSegmentedPicker(
                                selection: Binding(
                                    get: { Array(ErrorChartMode.allCases).firstIndex(of: errorChartMode) ?? 0 },
                                    set: { errorChartMode = Array(ErrorChartMode.allCases)[$0] }
                                ),
                                items: ErrorChartMode.allCases.map { $0.rawValue }
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .onChange(of: errorChartMode) { AppSettings.shared.errorChartMode = $0 }
                    }
                    Toggle("Show Residual Chart", isOn: $showResidualChart)
                        .onChange(of: showResidualChart) { AppSettings.shared.showResidualChart = $0 }
                }
                
                Section(header: Text("Storage & Background")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        UIKitSegmentedPicker(
                            selection: Binding(
                                get: { storageFormat == .json ? 0 : 1 },
                                set: { storageFormat = $0 == 0 ? .json : .sqlite }
                            ),
                            items: ["JSON File", "SQLite Database"]
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: storageFormat) { AppSettings.shared.storageFormat = $0 }
                    Toggle("Enable Background Logging", isOn: $enableBackgroundRecord)
                        .onChange(of: enableBackgroundRecord) { AppSettings.shared.enableBackgroundRecording = $0 }
                }
                
                Section(header: Text("Algorithm Control")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        UIKitSegmentedPicker(
                            selection: Binding(
                                get: { Array(SLAMFilterMode.allCases).firstIndex(of: slamFilterMode) ?? 0 },
                                set: { slamFilterMode = Array(SLAMFilterMode.allCases)[$0] }
                            ),
                            items: SLAMFilterMode.allCases.map { $0.rawValue }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: slamFilterMode) { AppSettings.shared.slamFilterMode = $0 }
                    
                    Toggle("Enable ZUPT", isOn: $enableZUPT)
                        .onChange(of: enableZUPT) { AppSettings.shared.enableZUPT = $0 }
                    
                    HStack { Label("Accel Threshold", systemImage: "speedometer"); Spacer(); TextField("Accel", text: $zuptAccStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptAccStr) { if let d = Double($0) { AppSettings.shared.zuptThreshold = d } } }
                    HStack { Label("Gyro Threshold", systemImage: "gyroscope"); Spacer(); TextField("Gyro", text: $zuptGyroStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptGyroStr) { if let d = Double($0) { AppSettings.shared.zuptGyroThreshold = d } } }
                }
                
                Section(header: Text("UI Toggles & Extra Logging")) {
                    Toggle("Auto Rotate (Heading Up)", isOn: $autoRotateCanvas)
                        .onChange(of: autoRotateCanvas) { AppSettings.shared.autoRotateCanvas = $0 }
                    Toggle("Log GNSS Data", isOn: $recordGNSS)
                        .onChange(of: recordGNSS) { AppSettings.shared.recordGNSS = $0 }
                    Toggle("Log Barometer Alt", isOn: $recordBarometer)
                        .onChange(of: recordBarometer) { AppSettings.shared.recordBarometer = $0 }
                    Toggle("Log 3-Axis Accel & Gyro", isOn: $recordAcceleration)
                        .onChange(of: recordAcceleration) { AppSettings.shared.recordAcceleration = $0 }
                }
            }
            .navigationTitle("Configuration")
            .sheet(isPresented: $showCalibration) { CalibrationView(onCalibrationDone: {}).environmentObject(engine) }
            .sheet(isPresented: $showAlignment) { SpatialCalibrationLabView().environmentObject(engine) }
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isInputActive = false; endTextEditing() }.font(.headline).foregroundColor(.blue)
                }
            }
            .onAppear {
                localNavMode = AppSettings.shared.coreNavMode
                
                timeStr = String(AppSettings.shared.recordIntervalTime)
                spaceStr = String(AppSettings.shared.recordIntervalSpace)
                biasXStr = String(AppSettings.shared.manualBiasX)
                biasYStr = String(AppSettings.shared.manualBiasY)
                biasZStr = String(AppSettings.shared.manualBiasZ)
                driftXStr = String(AppSettings.shared.driftCompX)
                driftYStr = String(AppSettings.shared.driftCompY)
                zuptAccStr = String(AppSettings.shared.zuptThreshold)
                zuptGyroStr = String(AppSettings.shared.zuptGyroThreshold)
            }
        }
    }
}

struct UIKitSegmentedPicker: UIViewRepresentable {
    @Binding var selection: Int
    let items: [String]
    
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selection
        control.apportionsSegmentWidthsByContent = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return control
    }
    
    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        if uiView.selectedSegmentIndex != selection {
            uiView.selectedSegmentIndex = selection
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: UIKitSegmentedPicker
        init(_ parent: UIKitSegmentedPicker) { self.parent = parent }
        @objc func valueChanged(_ sender: UISegmentedControl) {
            parent.selection = sender.selectedSegmentIndex
        }
    }
}

struct UIKitSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0.0...1.0
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return slider
    }
    
    func updateUIView(_ uiView: UISlider, context: Context) {
        if !uiView.isTracking && abs(Double(uiView.value) - value) > 0.001 {
            uiView.value = Float(value)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: UIKitSlider
        init(_ parent: UIKitSlider) { self.parent = parent }
        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
}

struct DebugPanelView: View {
    @State private var tab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                UIKitSegmentedPicker(selection: $tab, items: ["Sensors", "ML Info", "App Logs"])
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding()
            
            ScrollView {
                if tab == 0 {
                    SensorsTabView()
                } else if tab == 1 {
                    MLInfoTabView()
                } else {
                    AppLogsTabView()
                }
            }
        }
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SensorsTabView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(title: "ARKit VIO State", value: engine.debugState.arkitState)
            DebugRow(title: "AR Pos XYZ", value: String(format: "(%.2f, %.2f, %.2f)", engine.debugState.arkitPos.x, engine.debugState.arkitPos.y, engine.debugState.arkitPos.z))
            Divider()
            DebugRow(title: "Raw Earth Acc", value: String(format: "(%.3f, %.3f, %.3f)", engine.debugState.rawAcc.x, engine.debugState.rawAcc.y, engine.debugState.rawAcc.z))
            DebugRow(title: "Corrected Acc", value: String(format: "(%.3f, %.3f, %.3f)", engine.debugState.correctedAcc.x, engine.debugState.correctedAcc.y, engine.debugState.correctedAcc.z))
            DebugRow(title: "Raw Gyro", value: String(format: "(%.3f, %.3f, %.3f)", engine.debugState.rawGyro.x, engine.debugState.rawGyro.y, engine.debugState.rawGyro.z))
            Divider()
            DebugRow(title: "IMU Data FPS", value: String(format: "%.1f Hz", engine.debugState.imuFPS)).foregroundColor(.blue)
            DebugRow(title: "Mag Compass", value: String(format: "%.1f°", engine.debugState.compassHeading))
            DebugRow(title: "Barometer Alt", value: String(format: "%.2fm", engine.debugState.baroAlt))
        }.padding()
    }
}

struct MLInfoTabView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(title: "RoNIN Status", value: engine.debugState.mlStatus)
            DebugRow(title: "Predicted Vel (XY)", value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
            DebugRow(title: "RoNIN ML FPS", value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
            Text("Model Expects: [1, 6, 200] Float32/Double Array\n100Hz Hardware -> 200Hz Lerp Resampling")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top)
        }.padding()
    }
}

struct AppLogsTabView: View {
    @ObservedObject var logger = AppLogger.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(logger.logs, id: \.self) { log in
                Text(log).font(.system(size: 10, design: .monospaced)).foregroundColor(.green)
                Divider()
            }
        }.padding()
    }
}

struct DebugRow: View {
    var title: String; var value: String
    var body: some View {
        HStack {
            Text(title).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}
