import SwiftUI

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
                    Picker("Cascade Mode", selection: $localNavMode) {
                        ForEach(CoreNavMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: localNavMode) { m in
                        AppSettings.shared.coreNavMode = m
                        engine.switchNavMode(to: m)
                    }
                    
                    Button("Static Bias Calibration") { showCalibration = true }.foregroundColor(.blue)
                    Button("Spatial Alignment Lab") { showAlignment = true }.foregroundColor(.orange)
                    
                    // 这里传入环境对象，因为后续的子视图仍然需要访问 engine
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
                        Slider(value: $dampingX, in: 0.0...1.0)
                            .onChange(of: dampingX) { AppSettings.shared.dampingX = $0 }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Y-Axis Damping: \(String(format: "%.2f", dampingY))").font(.caption).foregroundColor(.gray)
                        Slider(value: $dampingY, in: 0.0...1.0)
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
                    Picker("Mode", selection: $recordingMode) { Text("By Time").tag(RecordingMode.time); Text("By Distance").tag(RecordingMode.distance) }
                        .pickerStyle(SegmentedPickerStyle())
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
                        Picker("Error Mode", selection: $errorChartMode) { ForEach(ErrorChartMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) } }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: errorChartMode) { AppSettings.shared.errorChartMode = $0 }
                    }
                    Toggle("Show Residual Chart", isOn: $showResidualChart)
                        .onChange(of: showResidualChart) { AppSettings.shared.showResidualChart = $0 }
                }
                
                Section(header: Text("Storage & Background")) {
                    Picker("Database Format", selection: $storageFormat) { Text("JSON File").tag(StorageFormat.json); Text("SQLite Database").tag(StorageFormat.sqlite) }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: storageFormat) { AppSettings.shared.storageFormat = $0 }
                    Toggle("Enable Background Logging", isOn: $enableBackgroundRecord)
                        .onChange(of: enableBackgroundRecord) { AppSettings.shared.enableBackgroundRecording = $0 }
                }
                
                Section(header: Text("Algorithm Control")) {
                    Picker("SLAM Filter", selection: $slamFilterMode) { ForEach(SLAMFilterMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) } }
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

struct DebugPanelView: View {
    @State private var tab = 0
    
    var body: some View {
        VStack {
            Picker("", selection: $tab) {
                Text("Sensors").tag(0)
                Text("ML Info").tag(1)
                Text("App Logs").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            DebugPanelContentView(tab: tab)
        }
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DebugPanelContentView: View {
    var tab: Int
    
    @EnvironmentObject var engine: SensorFusionEngine
    @ObservedObject var logger = AppLogger.shared
    
    var body: some View {
        ScrollView {
            if tab == 0 {
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
            } else if tab == 1 {
                VStack(alignment: .leading, spacing: 15) {
                    DebugRow(title: "RoNIN Status", value: engine.debugState.mlStatus)
                    DebugRow(title: "Predicted Vel (XY)", value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
                    DebugRow(title: "RoNIN ML FPS", value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
                    Text("Model Expects: [1, 6, 200] Float32/Double Array\n100Hz Hardware -> 200Hz Lerp Resampling")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top)
                }.padding()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(logger.logs, id: \.self) { log in
                        Text(log).font(.system(size: 10, design: .monospaced)).foregroundColor(.green)
                        Divider()
                    }
                }.padding()
            }
        }
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
