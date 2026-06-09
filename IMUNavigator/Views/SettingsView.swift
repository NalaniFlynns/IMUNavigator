import SwiftUI

extension View {
    func endTextEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    
    var body: some View {
        // 🌟 核心优化：使用 equatable() 彻底阻断 Engine 10Hz 刷新导致的 UI 视图重建
        // 保证所有滑块、开关和输入框 120Hz 丝滑响应，绝不吞手势！
        SettingsFormContent(engine: engine).equatable()
    }
}

struct SettingsFormContent: View, Equatable {
    var engine: SensorFusionEngine
    
    static func == (lhs: SettingsFormContent, rhs: SettingsFormContent) -> Bool {
        return true 
    }
    
    @StateObject private var settings = AppSettings.shared
    @State private var showCalibration = false
    @State private var showAlignment = false
    @FocusState private var isInputActive: Bool
    
    @State private var localNavMode: CoreNavMode = AppSettings.shared.coreNavMode
    
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
                        settings.coreNavMode = m
                        engine.switchNavMode(to: m)
                    }
                    
                    Button("Static Bias Calibration") { showCalibration = true }.foregroundColor(.blue)
                    Button("Spatial Alignment Lab") { showAlignment = true }.foregroundColor(.orange)
                    
                    NavigationLink(destination: DebugPanelView().environmentObject(engine)) {
                        HStack { Image(systemName: "terminal.fill"); Text("System Debug Console") }
                    }.foregroundColor(.purple)
                    
                    HStack { Text("Bias X"); Spacer(); TextField("X", text: $biasXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasXStr) { if let d = Double($0) { settings.manualBiasX = d } } }
                    HStack { Text("Bias Y"); Spacer(); TextField("Y", text: $biasYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasYStr) { if let d = Double($0) { settings.manualBiasY = d } } }
                    HStack { Text("Bias Z"); Spacer(); TextField("Z", text: $biasZStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasZStr) { if let d = Double($0) { settings.manualBiasZ = d } } }
                    
                    Toggle("Enable SLAM Position Correction", isOn: $settings.enableSLAMCorrection)
                    Toggle("Enable Dynamic Calibration (VIO)", isOn: $settings.enableDynamicCalibration)
                }
                
                Section(header: Text("Drift Compensation & Damping")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("X-Axis Damping: \(String(format: "%.2f", settings.dampingX))").font(.caption).foregroundColor(.gray)
                        Slider(value: $settings.dampingX, in: 0.0...1.0)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Y-Axis Damping: \(String(format: "%.2f", settings.dampingY))").font(.caption).foregroundColor(.gray)
                        Slider(value: $settings.dampingY, in: 0.0...1.0)
                    }
                    
                    HStack {
                        Label("Global X Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("X", text: $driftXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftXStr) { if let d = Double($0) { settings.driftCompX = d } }
                    }
                    HStack {
                        Label("Global Y Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("Y", text: $driftYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftYStr) { if let d = Double($0) { settings.driftCompY = d } }
                    }
                }
                
                Section(header: Text("Recording Mode")) {
                    Picker("Mode", selection: $settings.recordingMode) { Text("By Time").tag(RecordingMode.time); Text("By Distance").tag(RecordingMode.distance) }.pickerStyle(SegmentedPickerStyle())
                    if settings.recordingMode == .time {
                        HStack { Label("Time Interval (s)", systemImage: "clock"); Spacer(); TextField("0 = No limit", text: $timeStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: timeStr) { if let d = Double($0) { settings.recordIntervalTime = d } } }
                    } else {
                        HStack { Label("Space Interval (m)", systemImage: "ruler.fill"); Spacer(); TextField("0 = No limit", text: $spaceStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: spaceStr) { if let d = Double($0) { settings.recordIntervalSpace = d } } }
                    }
                }
                
                Section(header: Text("Charts Display")) {
                    Toggle("Show Altitude Chart", isOn: $settings.showAltitudeChart)
                    Toggle("Show Error Chart", isOn: $settings.showErrorChart)
                    if settings.showErrorChart {
                        Picker("Error Mode", selection: $settings.errorChartMode) { ForEach(ErrorChartMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) } }.pickerStyle(SegmentedPickerStyle())
                    }
                    Toggle("Show Residual Chart", isOn: $settings.showResidualChart)
                }
                
                Section(header: Text("Storage & Background")) {
                    Picker("Database Format", selection: $settings.storageFormat) { Text("JSON File").tag(StorageFormat.json); Text("SQLite Database").tag(StorageFormat.sqlite) }.pickerStyle(SegmentedPickerStyle())
                    Toggle("Enable Background Logging", isOn: $settings.enableBackgroundRecording)
                }
                
                Section(header: Text("Algorithm Control")) {
                    Picker("SLAM Filter", selection: $settings.slamFilterMode) { ForEach(SLAMFilterMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) } }
                    Toggle("Enable ZUPT", isOn: $settings.enableZUPT)
                    
                    HStack { Label("Accel Threshold", systemImage: "speedometer"); Spacer(); TextField("Accel", text: $zuptAccStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptAccStr) { if let d = Double($0) { settings.zuptThreshold = d } } }
                    HStack { Label("Gyro Threshold", systemImage: "gyroscope"); Spacer(); TextField("Gyro", text: $zuptGyroStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptGyroStr) { if let d = Double($0) { settings.zuptGyroThreshold = d } } }
                }
                
                Section(header: Text("UI Toggles & Extra Logging")) {
                    Toggle("Auto Rotate (Heading Up)", isOn: $settings.autoRotateCanvas)
                    Toggle("Log GNSS Data", isOn: $settings.recordGNSS)
                    Toggle("Log Barometer Alt", isOn: $settings.recordBarometer)
                    Toggle("Log 3-Axis Accel & Gyro", isOn: $settings.recordAcceleration)
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
                timeStr = String(settings.recordIntervalTime)
                spaceStr = String(settings.recordIntervalSpace)
                biasXStr = String(settings.manualBiasX)
                biasYStr = String(settings.manualBiasY)
                biasZStr = String(settings.manualBiasZ)
                driftXStr = String(settings.driftCompX)
                driftYStr = String(settings.driftCompY)
                zuptAccStr = String(settings.zuptThreshold)
                zuptGyroStr = String(settings.zuptGyroThreshold)
            }
        }
    }
}

struct DebugPanelView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    @State private var tab = 0
    @ObservedObject var logger = AppLogger.shared
    
    var body: some View {
        VStack {
            Picker("", selection: $tab) {
                Text("Sensors").tag(0)
                Text("ML Info").tag(1)
                Text("App Logs").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
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
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
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
