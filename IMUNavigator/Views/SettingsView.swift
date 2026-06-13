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
    
    @State private var navModeIndex: Int = Array(CoreNavMode.allCases).firstIndex(of: AppSettings.shared.coreNavMode) ?? 0
    @State private var recordingModeIndex: Int = AppSettings.shared.recordingMode == .time ? 0 : 1
    @State private var errorChartModeIndex: Int = Array(ErrorChartMode.allCases).firstIndex(of: AppSettings.shared.errorChartMode) ?? 0
    @State private var storageFormatIndex: Int = AppSettings.shared.storageFormat == .json ? 0 : 1
    @State private var slamFilterModeIndex: Int = Array(SLAMFilterMode.allCases).firstIndex(of: AppSettings.shared.slamFilterMode) ?? 0
    
    @State private var dampingX: Double = AppSettings.shared.dampingX
    @State private var dampingY: Double = AppSettings.shared.dampingY
    @State private var enableSLAM: Bool = AppSettings.shared.enableSLAMCorrection
    @State private var enableDynamicCalib: Bool = AppSettings.shared.enableDynamicCalibration
    @State private var showAltitudeChart: Bool = AppSettings.shared.showAltitudeChart
    @State private var showErrorChart: Bool = AppSettings.shared.showErrorChart
    @State private var showResidualChart: Bool = AppSettings.shared.showResidualChart
    @State private var enableBackgroundRecord: Bool = AppSettings.shared.enableBackgroundRecording
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
                            selection: $navModeIndex,
                            items: CoreNavMode.allCases.map { $0.rawValue }
                        )
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)
                        .onChange(of: navModeIndex) { _, newIndex in
                            let selectedMode = Array(CoreNavMode.allCases)[newIndex]
                            AppSettings.shared.coreNavMode = selectedMode
                            engine.switchNavMode(to: selectedMode)
                        }
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
                        selection: $recordingModeIndex,
                        items: ["By Time", "By Distance"]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: recordingModeIndex) { _, newIndex in
                        let mode: RecordingMode = newIndex == 0 ? .time : .distance
                        AppSettings.shared.recordingMode = mode
                    }
                    
                    if recordingModeIndex == 0 {
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
                            selection: $errorChartModeIndex,
                            items: ErrorChartMode.allCases.map { $0.rawValue }
                        )
                        .frame(height: 32).frame(maxWidth: .infinity)
                        .onChange(of: errorChartModeIndex) { _, newIndex in
                            let mode = Array(ErrorChartMode.allCases)[newIndex]
                            AppSettings.shared.errorChartMode = mode
                        }
                    }
                    
                    Toggle("Show Residual Chart", isOn: $showResidualChart)
                        .onChange(of: showResidualChart) { _, newValue in AppSettings.shared.showResidualChart = newValue }
                }
                
                Section(header: Text("Storage & Background")) {
                    UIKitSegmentedPicker(
                        selection: $storageFormatIndex,
                        items: ["JSON File", "SQLite Database"]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: storageFormatIndex) { _, newIndex in
                        let fmt: StorageFormat = newIndex == 0 ? .json : .sqlite
                        AppSettings.shared.storageFormat = fmt
                    }
                    
                    Toggle("Enable Background Logging", isOn: $enableBackgroundRecord)
                        .onChange(of: enableBackgroundRecord) { _, newValue in AppSettings.shared.enableBackgroundRecording = newValue }
                }
                
                Section(header: Text("Algorithm Control")) {
                    UIKitSegmentedPicker(
                        selection: $slamFilterModeIndex,
                        items: SLAMFilterMode.allCases.map { $0.rawValue }
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: slamFilterModeIndex) { _, newIndex in
                        let mode = Array(SLAMFilterMode.allCases)[newIndex]
                        AppSettings.shared.slamFilterMode = mode
                    }
                    
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
            .onReceive(syncTimer) { _ in
                let currentNavMode = AppSettings.shared.coreNavMode
                let expectedIndex = Array(CoreNavMode.allCases).firstIndex(of: currentNavMode) ?? 0
                if navModeIndex != expectedIndex {
                    navModeIndex = expectedIndex
                }
            }
            .onAppear {
                navModeIndex = Array(CoreNavMode.allCases).firstIndex(of: AppSettings.shared.coreNavMode) ?? 0
                recordingModeIndex = AppSettings.shared.recordingMode == .time ? 0 : 1
                errorChartModeIndex = Array(ErrorChartMode.allCases).firstIndex(of: AppSettings.shared.errorChartMode) ?? 0
                storageFormatIndex = AppSettings.shared.storageFormat == .json ? 0 : 1
                slamFilterModeIndex = Array(SLAMFilterMode.allCases).firstIndex(of: AppSettings.shared.slamFilterMode) ?? 0
                
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
        context.coordinator.parent = self
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
        context.coordinator.parent = self
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
    
    // --- 图表功能状态 ---
    @State private var chartModeIndex: Int = 1 // 0: IMU vs ML 对比, 1: NR vs AR 残差对比
    @State private var timeRangeMode: Int = 1 // 0: 全局Global, 1: 时间窗口Window
    @State private var timeWindowDuration: Double = 30.0 // 时间窗口长度 (1秒 ~ 300秒)
    @State private var chartScaleLevel: Int = 1 // 比例尺精度: 0: Coarse, 1: Normal, 2: Fine
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(icon: "cpu", title: "NR Mode Status", value: engine.debugState.mlStatus)
            DebugRow(icon: "move.3d", title: "NR Predicted Vel", value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
            DebugRow(icon: "bolt.badge.clock.fill", title: "NR Processing FPS", value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
            
            Divider()
            
            // --- 控制面板 ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Chart Configuration").font(.headline).foregroundColor(.primary)
                
                UIKitSegmentedPicker(selection: $chartModeIndex, items: ["IMU vs ML", "NR vs AR"])
                    .frame(height: 32)
                
                UIKitSegmentedPicker(selection: $timeRangeMode, items: ["Global History", "Time Window"])
                    .frame(height: 32)
                
                if timeRangeMode == 1 {
                    HStack {
                        Text("Window: \(Int(timeWindowDuration))s").font(.subheadline).frame(width: 90, alignment: .leading)
                        UIKitSlider(value: $timeWindowDuration, range: 1.0...300.0)
                    }
                }
                
                HStack {
                    Text("Precision Scale:").font(.subheadline).frame(width: 120, alignment: .leading)
                    UIKitSegmentedPicker(selection: $chartScaleLevel, items: ["Coarse", "Normal", "Fine"])
                        .frame(height: 32)
                }
            }
            .padding(.bottom, 5)
            
            // --- 数据过滤与X轴比例尺准备 ---
            let allPoints = engine.chartPoints
            let baseTime = allPoints.first?.timestamp ?? 0
            let maxTime = allPoints.last?.timestamp ?? 0
            
            // 计算X轴的下限，以此筛选渲染点，并为Chart构建完美的Domain缩放
            let minTime = timeRangeMode == 0 ? baseTime : max(baseTime, maxTime - timeWindowDuration)
            let displayPoints = timeRangeMode == 0 ? allPoints : allPoints.filter { $0.timestamp >= minTime }
            
            let domainMin = minTime - baseTime
            let domainMax = max(domainMin + 1.0, maxTime - baseTime) // 防止 domain 宽度为 0 导致崩溃
            
            // 动态高度解析（图表越高，Y轴显示精度就越好）
            let chartHeight: CGFloat = chartScaleLevel == 0 ? 100 : (chartScaleLevel == 1 ? 160 : 260)
            
            if chartModeIndex == 0 {
                // --- 模式 1：IMU 输入与 ML 输出对比 ---
                let accX = engine.debugState.correctedAcc.x
                let accY = engine.debugState.correctedAcc.y
                let mlSpeed = hypot(engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y)
                
                let avgAccX = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.x }.reduce(0, +) / Double(displayPoints.count)
                let avgAccY = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.y }.reduce(0, +) / Double(displayPoints.count)
                let avgSpeed = displayPoints.isEmpty ? 0 : displayPoints.map { $0.speed }.reduce(0, +) / Double(displayPoints.count)
                
                // 【核心修改】动态计算当前显示窗口内 Y 轴的最极值
                let chart1Min = min(
                    displayPoints.compactMap { $0.acceleration?.x }.min() ?? 0,
                    displayPoints.compactMap { $0.acceleration?.y }.min() ?? 0,
                    displayPoints.map { $0.speed }.min() ?? 0
                )
                let chart1Max = max(
                    displayPoints.compactMap { $0.acceleration?.x }.max() ?? 0,
                    displayPoints.compactMap { $0.acceleration?.y }.max() ?? 0,
                    displayPoints.map { $0.speed }.max() ?? 0
                )
                let c1Span = max(chart1Max - chart1Min, 0.01) // 防止全0直线崩溃
                let c1Domain = (chart1Min - c1Span * 0.1)...(chart1Max + c1Span * 0.1) // 留10%裕量
                
                DebugRow(icon: "waveform.path", title: "IMU Accel X", value: String(format: "%.3f (Avg: %.3f)", accX, avgAccX))
                    .foregroundColor(.green)
                DebugRow(icon: "waveform.path", title: "IMU Accel Y", value: String(format: "%.3f (Avg: %.3f)", accY, avgAccY))
                    .foregroundColor(.yellow)
                DebugRow(icon: "speedometer", title: "ML Output Speed", value: String(format: "%.3f (Avg: %.3f)", mlSpeed, avgSpeed))
                    .foregroundColor(.purple)
                
                if !engine.chartPoints.isEmpty {
                    Chart {
                        ForEach(displayPoints) { point in
                            let time = point.timestamp - baseTime
                            
                            LineMark(
                                x: .value("Time", time),
                                y: .value("Value", point.acceleration?.x ?? 0.0)
                            )
                            .foregroundStyle(by: .value("Metric", "Acc X"))
                            
                            LineMark(
                                x: .value("Time", time),
                                y: .value("Value", point.acceleration?.y ?? 0.0)
                            )
                            .foregroundStyle(by: .value("Metric", "Acc Y"))
                            
                            LineMark(
                                x: .value("Time", time),
                                y: .value("Value", point.speed)
                            )
                            .foregroundStyle(by: .value("Metric", "ML Speed"))
                        }
                        
                        // 绘制均值虚线
                        RuleMark(y: .value("Avg Acc X", avgAccX))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.green.opacity(0.8))
                        
                        RuleMark(y: .value("Avg Acc Y", avgAccY))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.yellow.opacity(0.8))
                            
                        RuleMark(y: .value("Avg Speed", avgSpeed))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.purple.opacity(0.8))
                    }
                    .chartForegroundStyleScale([
                        "Acc X": .green,
                        "Acc Y": .yellow,
                        "ML Speed": .purple
                    ])
                    .chartXScale(domain: domainMin...domainMax)
                    .chartYScale(domain: c1Domain) // 强制覆写 Y 轴比例尺极值
                    .chartXAxis(.hidden)
                    .frame(height: chartHeight)
                }
                
            } else {
                // --- 模式 2：NR 与 AR 输出对比（残差）---
                let xRes = engine.chartPoints.last?.resX ?? 0.0
                let yRes = engine.chartPoints.last?.resY ?? 0.0
                
                let avgXRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resX }.reduce(0, +) / Double(displayPoints.count)
                let avgYRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resY }.reduce(0, +) / Double(displayPoints.count)
                
                // 【核心修改】动态计算当前显示窗口内 Y 轴的最极值
                let chart2Min = min(
                    displayPoints.compactMap { $0.resX }.min() ?? 0,
                    displayPoints.compactMap { $0.resY }.min() ?? 0
                )
                let chart2Max = max(
                    displayPoints.compactMap { $0.resX }.max() ?? 0,
                    displayPoints.compactMap { $0.resY }.max() ?? 0
                )
                let c2Span = max(chart2Max - chart2Min, 0.01) // 防止全0直线崩溃
                let c2Domain = (chart2Min - c2Span * 0.1)...(chart2Max + c2Span * 0.1) // 留10%裕量
                
                DebugRow(icon: "arrow.left.and.right", title: "X-Axis Residual", value: String(format: "%.3f m (Avg: %.3f)", xRes, avgXRes))
                    .foregroundColor(.blue)
                DebugRow(icon: "arrow.up.and.down", title: "Y-Axis Residual", value: String(format: "%.3f m (Avg: %.3f)", yRes, avgYRes))
                    .foregroundColor(.red)
                
                if !engine.chartPoints.isEmpty {
                    Chart {
                        ForEach(displayPoints) { point in
                            let time = point.timestamp - baseTime
                            
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
                        
                        // 绘制均值虚线
                        RuleMark(y: .value("Avg X", avgXRes))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.blue.opacity(0.8))
                            
                        RuleMark(y: .value("Avg Y", avgYRes))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .chartForegroundStyleScale([
                        "X Res": .blue,
                        "Y Res": .red
                    ])
                    .chartXScale(domain: domainMin...domainMax)
                    .chartYScale(domain: c2Domain) // 强制覆写 Y 轴比例尺极值
                    .chartXAxis(.hidden)
                    .frame(height: chartHeight)
                }
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
