import SwiftUI
import UIKit
import Charts
import Combine

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
    
    let syncTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Core Routing Engine")) {
                    VStack(alignment: .leading, spacing: 5) {
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
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)
                    }
                    
                    Button("Static Bias Calibration") { showCalibration = true }.foregroundColor(.blue)
                    Button("Spatial Alignment Lab") { showAlignment = true }.foregroundColor(.orange)
                    
                    NavigationLink(destination: DebugPanelView().environmentObject(engine)) {
                        HStack { Image(systemName: "terminal.fill"); Text("System Debug Console") }
                    }.foregroundColor(.purple)
                    
                    HStack { Text("Bias X"); Spacer(); TextField("X", text: $biasXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasXStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasX = d } } }
                    HStack { Text("Bias Y"); Spacer(); TextField("Y", text: $biasYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasYStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasY = d } } }
                    HStack { Text("Bias Z"); Spacer(); TextField("Z", text: $biasZStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasZStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasZ = d } } }
                    
                    Toggle("Enable SLAM Position Correction", isOn: $enableSLAM)
                        .onChange(of: enableSLAM) { _, newValue in AppSettings.shared.enableSLAMCorrection = newValue }
                    Toggle("Enable Dynamic Calibration (VIO)", isOn: $enableDynamicCalib)
                        .onChange(of: enableDynamicCalib) { _, newValue in AppSettings.shared.enableDynamicCalibration = newValue }
                }
                
                Section(header: Text("Drift Compensation & Damping")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("X-Axis Damping: \(String(format: "%.2f", dampingX))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingX, range: 0.0...1.0)
                            .onChange(of: dampingX) { _, newValue in AppSettings.shared.dampingX = newValue }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Y-Axis Damping: \(String(format: "%.2f", dampingY))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingY, range: 0.0...1.0)
                            .onChange(of: dampingY) { _, newValue in AppSettings.shared.dampingY = newValue }
                    }
                    
                    HStack {
                        Label("Global X Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("X", text: $driftXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftXStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.driftCompX = d } }
                    }
                    HStack {
                        Label("Global Y Drift (m/s)", systemImage: "move.3d")
                        Spacer()
                        TextField("Y", text: $driftYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftYStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.driftCompY = d } }
                    }
                }
                
                Section(header: Text("Recording Mode")) {
                    UIKitSegmentedPicker(
                        selection: Binding(
                            get: { recordingMode == .time ? 0 : 1 },
                            set: { newIndex in 
                                let mode: RecordingMode = newIndex == 0 ? .time : .distance
                                recordingMode = mode
                                AppSettings.shared.recordingMode = mode
                            }
                        ),
                        items: ["By Time", "By Distance"]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    
                    if recordingMode == .time {
                        HStack { Label("Time Interval (s)", systemImage: "clock"); Spacer(); TextField("0 = No limit", text: $timeStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: timeStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.recordIntervalTime = d } } }
                    } else {
                        HStack { Label("Space Interval (m)", systemImage: "ruler.fill"); Spacer(); TextField("0 = No limit", text: $spaceStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: spaceStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.recordIntervalSpace = d } } }
                    }
                }
                
                Section(header: Text("Charts Display")) {
                    Toggle("Show Altitude Chart", isOn: $showAltitudeChart)
                        .onChange(of: showAltitudeChart) { _, newValue in AppSettings.shared.showAltitudeChart = newValue }
                    Toggle("Show Error Chart", isOn: $showErrorChart)
                        .onChange(of: showErrorChart) { _, newValue in AppSettings.shared.showErrorChart = newValue }
                    if showErrorChart {
                        UIKitSegmentedPicker(
                            selection: Binding(
                                get: { Array(ErrorChartMode.allCases).firstIndex(of: errorChartMode) ?? 0 },
                                set: { newIndex in 
                                    let mode = Array(ErrorChartMode.allCases)[newIndex]
                                    errorChartMode = mode
                                    AppSettings.shared.errorChartMode = mode
                                }
                            ),
                            items: ErrorChartMode.allCases.map { $0.rawValue }
                        )
                        .frame(height: 32).frame(maxWidth: .infinity)
                    }
                    Toggle("Show Residual Chart", isOn: $showResidualChart)
                        .onChange(of: showResidualChart) { _, newValue in AppSettings.shared.showResidualChart = newValue }
                }
                
                Section(header: Text("Storage & Background")) {
                    UIKitSegmentedPicker(
                        selection: Binding(
                            get: { storageFormat == .json ? 0 : 1 },
                            set: { newIndex in 
                                let fmt: StorageFormat = newIndex == 0 ? .json : .sqlite
                                storageFormat = fmt
                                AppSettings.shared.storageFormat = fmt
                            }
                        ),
                        items: ["JSON File", "SQLite Database"]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    Toggle("Enable Background Logging", isOn: $enableBackgroundRecord)
                        .onChange(of: enableBackgroundRecord) { _, newValue in AppSettings.shared.enableBackgroundRecording = newValue }
                }
                
                Section(header: Text("Algorithm Control")) {
                    UIKitSegmentedPicker(
                        selection: Binding(
                            get: { Array(SLAMFilterMode.allCases).firstIndex(of: slamFilterMode) ?? 0 },
                            set: { newIndex in 
                                let mode = Array(SLAMFilterMode.allCases)[newIndex]
                                slamFilterMode = mode
                                AppSettings.shared.slamFilterMode = mode
                            }
                        ),
                        items: SLAMFilterMode.allCases.map { $0.rawValue }
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    
                    Toggle("Enable ZUPT", isOn: $enableZUPT)
                        .onChange(of: enableZUPT) { _, newValue in AppSettings.shared.enableZUPT = newValue }
                    
                    HStack { Label("Accel Threshold", systemImage: "speedometer"); Spacer(); TextField("Accel", text: $zuptAccStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptAccStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.zuptThreshold = d } } }
                    HStack { Label("Gyro Threshold", systemImage: "gyroscope"); Spacer(); TextField("Gyro", text: $zuptGyroStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptGyroStr) { _, newValue in if let d = Double(newValue) { AppSettings.shared.zuptGyroThreshold = d } } }
                }
                
                Section(header: Text("UI Toggles & Extra Logging")) {
                    Toggle("Auto Rotate (Heading Up)", isOn: $autoRotateCanvas)
                        .onChange(of: autoRotateCanvas) { _, newValue in AppSettings.shared.autoRotateCanvas = newValue }
                    Toggle("Log GNSS Data", isOn: $recordGNSS)
                        .onChange(of: recordGNSS) { _, newValue in AppSettings.shared.recordGNSS = newValue }
                    Toggle("Log Barometer Alt", isOn: $recordBarometer)
                        .onChange(of: recordBarometer) { _, newValue in AppSettings.shared.recordBarometer = newValue }
                    Toggle("Log 3-Axis Accel & Gyro", isOn: $recordAcceleration)
                        .onChange(of: recordAcceleration) { _, newValue in AppSettings.shared.recordAcceleration = newValue }
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
            // 后台轻量级监听底层模式变化，实现降级后 UI 的自动纠正
            .onReceive(syncTimer) { _ in
                if localNavMode != AppSettings.shared.coreNavMode {
                    localNavMode = AppSettings.shared.coreNavMode
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
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        

        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        

        control.apportionsSegmentWidthsByContent = false
        

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle
        ]
        
        control.setTitleTextAttributes(attributes, for: .normal)
        control.setTitleTextAttributes(attributes, for: .selected)
        control.setTitleTextAttributes(attributes, for: .highlighted)
        
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
            UIKitSegmentedPicker(selection: $tab, items: ["Sensors", "ML Info", "App Logs"])
                .frame(height: 32)
                .frame(maxWidth: .infinity)
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
    @State private var tick = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(icon: "cpu", title: "NR Mode Status", value: engine.debugState.mlStatus)
            DebugRow(icon: "move.3d", title: "NR Predicted Vel", value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
            DebugRow(icon: "bolt.badge.clock.fill", title: "NR Processing FPS", value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
            
            Divider()
            Label("Data Compare: XY Residuals", systemImage: "chart.xyaxis.line").font(.headline).foregroundColor(.primary)
        
            let xRes = engine.chartPoints.last?.resX ?? 0.0
            let yRes = engine.chartPoints.last?.resY ?? 0.0
            
            DebugRow(icon: "arrow.left.and.right", title: "X-Axis Residual", value: String(format: "%.3f m", xRes))
                .foregroundColor(.blue)
            DebugRow(icon: "arrow.up.and.down", title: "Y-Axis Residual", value: String(format: "%.3f m", yRes))
                .foregroundColor(.red)
            
            if !engine.chartPoints.isEmpty {
                Chart {
                    let firstTime = engine.chartPoints.first?.timestamp ?? 0
                    ForEach(engine.chartPoints) { point in
                        let time = point.timestamp - firstTime
                        
                        LineMark(
                            x: .value("Time", time),
                            y: .value("Error", point.resX ?? 0.0)
                        )
                        .foregroundStyle(by: .value("Axis", "X Res"))
                        
                        LineMark(
                            x: .value("Time", time),
                            y: .value("Error", point.resY ?? 0.0)
                        )
                        .foregroundStyle(by: .value("Axis", "Y Res"))
                    }
                }
                .chartForegroundStyleScale([
                    "X Res": .blue,
                    "Y Res": .red
                ])
                .chartXAxis(.hidden)
                .frame(height: 100)
            }
            
            Text("Model Expects: [1, 6, 200] Float32/Double Array\n100Hz Hardware -> 200Hz Lerp Resampling")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top)
        }
        .padding()
        .onReceive(timer) { _ in
            tick &+= 1
        }
        .background(Color.clear.opacity(Double(tick % 2) * 0.00001))
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
    var icon: String? = nil
    var title: String
    var value: String
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon).foregroundColor(.gray).frame(width: 20, alignment: .leading)
            }
            Text(title).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}
