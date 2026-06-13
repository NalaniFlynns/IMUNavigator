import SwiftUI
import UIKit
import Charts
import Combine

func l(_ en: String, _ zh: String) -> String {
    let lang = Locale.current.languageCode ?? "en"
    return lang.hasPrefix("zh") ? zh : en
}

extension View {
    func endTextEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

class ImageCache {
    static let shared = ImageCache()
    var cache: [String: UIImage] = [:]
}

class ImageSaver: NSObject {
    static let shared = ImageSaver()
    var onComplete: (() -> Void)?
    
    func writeToPhotoAlbum(image: UIImage, completion: @escaping () -> Void) {
        self.onComplete = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }
    
    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        onComplete?()
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
    
    @State private var updateStatus: String = l("Check for Updates", "检查更新")
    
    let syncTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(l("Core Routing Engine", "核心路由引擎"))) {
                    VStack(alignment: .leading, spacing: 5) {
                        UIKitSegmentedPicker(
                            selection: $navModeIndex,
                            items: CoreNavMode.allCases.map { $0.rawValue }
                        )
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)
                        .onChange(of: navModeIndex) { newIndex in
                            let selectedMode = Array(CoreNavMode.allCases)[newIndex]
                            AppSettings.shared.coreNavMode = selectedMode
                            engine.switchNavMode(to: selectedMode)
                        }
                    }
                    
                    Button(l("Static Bias Calibration", "静态偏置校准")) { showCalibration = true }.foregroundColor(.blue)
                    Button(l("Spatial Alignment Lab", "空间对齐实验室")) { showAlignment = true }.foregroundColor(.orange)
                    
                    NavigationLink(destination: DebugPanelView().environmentObject(engine)) {
                        HStack { Image(systemName: "terminal"); Text(l("System Debug Console", "系统调试控制台")) }
                    }.foregroundColor(.purple)
                    
                    HStack { Text(l("Bias X", "偏置 X")); Spacer(); TextField("X", text: $biasXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasXStr) { newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasX = d } } }
                    HStack { Text(l("Bias Y", "偏置 Y")); Spacer(); TextField("Y", text: $biasYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasYStr) { newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasY = d } } }
                    HStack { Text(l("Bias Z", "偏置 Z")); Spacer(); TextField("Z", text: $biasZStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 80).onChange(of: biasZStr) { newValue in if let d = Double(newValue) { AppSettings.shared.manualBiasZ = d } } }
                    
                    Toggle(l("Enable SLAM Position Correction", "启用 SLAM 位置修正"), isOn: $enableSLAM)
                        .onChange(of: enableSLAM) { newValue in AppSettings.shared.enableSLAMCorrection = newValue }
                    Toggle(l("Enable Dynamic Calibration (VIO)", "启用动态校准 (VIO)"), isOn: $enableDynamicCalib)
                        .onChange(of: enableDynamicCalib) { newValue in AppSettings.shared.enableDynamicCalibration = newValue }
                }
                
                Section(header: Text(l("Drift Compensation & Damping", "漂移补偿与阻尼"))) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(l("X-Axis Damping:", "X轴阻尼:")) \(String(format: "%.2f", dampingX))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingX, range: 0.0...1.0)
                            .onChange(of: dampingX) { newValue in AppSettings.shared.dampingX = newValue }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(l("Y-Axis Damping:", "Y轴阻尼:")) \(String(format: "%.2f", dampingY))").font(.caption).foregroundColor(.gray)
                        UIKitSlider(value: $dampingY, range: 0.0...1.0)
                            .onChange(of: dampingY) { newValue in AppSettings.shared.dampingY = newValue }
                    }
                    
                    HStack {
                        Label(l("Global X Drift (m/s)", "全局 X 轴漂移 (m/s)"), systemImage: "move.3d")
                        Spacer()
                        TextField("X", text: $driftXStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftXStr) { newValue in if let d = Double(newValue) { AppSettings.shared.driftCompX = d } }
                    }
                    HStack {
                        Label(l("Global Y Drift (m/s)", "全局 Y 轴漂移 (m/s)"), systemImage: "move.3d")
                        Spacer()
                        TextField("Y", text: $driftYStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).frame(width: 60).onChange(of: driftYStr) { newValue in if let d = Double(newValue) { AppSettings.shared.driftCompY = d } }
                    }
                }
                
                Section(header: Text(l("Recording Mode", "记录模式"))) {
                    UIKitSegmentedPicker(
                        selection: $recordingModeIndex,
                        items: [l("By Time", "按时间"), l("By Distance", "按距离")]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: recordingModeIndex) { newIndex in
                        let mode: RecordingMode = newIndex == 0 ? .time : .distance
                        AppSettings.shared.recordingMode = mode
                    }
                    
                    if recordingModeIndex == 0 {
                        HStack { Label(l("Time Interval (s)", "时间间隔 (秒)"), systemImage: "clock"); Spacer(); TextField(l("0 = No limit", "0 = 无限制"), text: $timeStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: timeStr) { newValue in if let d = Double(newValue) { AppSettings.shared.recordIntervalTime = d } } }
                    } else {
                        HStack { Label(l("Space Interval (m)", "距离间隔 (米)"), systemImage: "ruler"); Spacer(); TextField(l("0 = No limit", "0 = 无限制"), text: $spaceStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: spaceStr) { newValue in if let d = Double(newValue) { AppSettings.shared.recordIntervalSpace = d } } }
                    }
                }
                
                Section(header: Text(l("Charts Display", "图表显示"))) {
                    Toggle(l("Show Altitude Chart", "显示高度图表"), isOn: $showAltitudeChart)
                        .onChange(of: showAltitudeChart) { newValue in AppSettings.shared.showAltitudeChart = newValue }
                    Toggle(l("Show Error Chart", "显示误差图表"), isOn: $showErrorChart)
                        .onChange(of: showErrorChart) { newValue in AppSettings.shared.showErrorChart = newValue }
                    
                    if showErrorChart {
                        UIKitSegmentedPicker(
                            selection: $errorChartModeIndex,
                            items: ErrorChartMode.allCases.map { $0.rawValue }
                        )
                        .frame(height: 32).frame(maxWidth: .infinity)
                        .onChange(of: errorChartModeIndex) { newIndex in
                            let mode = Array(ErrorChartMode.allCases)[newIndex]
                            AppSettings.shared.errorChartMode = mode
                        }
                    }
                    
                    Toggle(l("Show Residual Chart", "显示残差图表"), isOn: $showResidualChart)
                        .onChange(of: showResidualChart) { newValue in AppSettings.shared.showResidualChart = newValue }
                }
                
                Section(header: Text(l("Storage & Background", "存储与后台"))) {
                    UIKitSegmentedPicker(
                        selection: $storageFormatIndex,
                        items: [l("JSON File", "JSON 文件"), l("SQLite Database", "SQLite 数据库")]
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: storageFormatIndex) { newIndex in
                        let fmt: StorageFormat = newIndex == 0 ? .json : .sqlite
                        AppSettings.shared.storageFormat = fmt
                    }
                    
                    Toggle(l("Enable Background Logging", "启用后台记录"), isOn: $enableBackgroundRecord)
                        .onChange(of: enableBackgroundRecord) { newValue in AppSettings.shared.enableBackgroundRecording = newValue }
                }
                
                Section(header: Text(l("Algorithm Control", "算法控制"))) {
                    UIKitSegmentedPicker(
                        selection: $slamFilterModeIndex,
                        items: SLAMFilterMode.allCases.map { $0.rawValue }
                    )
                    .frame(height: 32).frame(maxWidth: .infinity)
                    .onChange(of: slamFilterModeIndex) { newIndex in
                        let mode = Array(SLAMFilterMode.allCases)[newIndex]
                        AppSettings.shared.slamFilterMode = mode
                    }
                    
                    Toggle(l("Enable ZUPT", "启用 ZUPT (零速修正)"), isOn: $enableZUPT)
                        .onChange(of: enableZUPT) { newValue in AppSettings.shared.enableZUPT = newValue }
                    
                    HStack { Label(l("Accel Threshold", "加速度阈值"), systemImage: "speedometer"); Spacer(); TextField("Accel", text: $zuptAccStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptAccStr) { newValue in if let d = Double(newValue) { AppSettings.shared.zuptThreshold = d } } }
                    HStack { Label(l("Gyro Threshold", "陀螺仪阈值"), systemImage: "gyroscope"); Spacer(); TextField("Gyro", text: $zuptGyroStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputActive).onChange(of: zuptGyroStr) { newValue in if let d = Double(newValue) { AppSettings.shared.zuptGyroThreshold = d } } }
                }
                
                Section(header: Text(l("UI Toggles & Extra Logging", "UI 选项与额外日志"))) {
                    Toggle(l("Auto Rotate (Heading Up)", "自动旋转 (机头朝上)"), isOn: $autoRotateCanvas)
                        .onChange(of: autoRotateCanvas) { newValue in AppSettings.shared.autoRotateCanvas = newValue }
                    Toggle(l("Log GNSS Data", "记录 GNSS 数据"), isOn: $recordGNSS)
                        .onChange(of: recordGNSS) { newValue in AppSettings.shared.recordGNSS = newValue }
                    Toggle(l("Log Barometer Alt", "记录气压计高度"), isOn: $recordBarometer)
                        .onChange(of: recordBarometer) { newValue in AppSettings.shared.recordBarometer = newValue }
                    Toggle(l("Log 3-Axis Accel & Gyro", "记录三轴加速度与陀螺仪"), isOn: $recordAcceleration)
                        .onChange(of: recordAcceleration) { newValue in AppSettings.shared.recordAcceleration = newValue }
                }
                
                Section(header: Text(l("About & Support", "关于与支持"))) {
                    VStack(spacing: 12) {
                        HStack(spacing: 15) {
                            Image(systemName: "gyroscope")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("IMUNavigator")
                                    .font(.headline)
                                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                                Text("\(l("Version", "版本")) \(version) (\(l("Build", "构建")) \(build))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        Divider()
                        
                        Link(destination: URL(string: "https://github.com/nalaniflynns/imunavigator")!) {
                            HStack {
                                Image(systemName: "curlybraces")
                                    .frame(width: 24)
                                Text(l("GitHub Repository", "GitHub 仓库"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                        
                        Link(destination: URL(string: "https://github.com/nalaniflynns/imunavigator/issues")!) {
                            HStack {
                                Image(systemName: "ladybug")
                                    .frame(width: 24)
                                Text(l("Submit Feedback", "提交反馈"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                        
                        NavigationLink(destination: SponsorView()) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .frame(width: 24)
                                    .foregroundColor(.pink)
                                Text(l("Support the Developer", "支持开发者"))
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button(action: {
                            checkForUpdates(manual: true)
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .frame(width: 24)
                                    .foregroundColor(.gray)
                                Text(updateStatus)
                                Spacer()
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .onAppear {
                            checkForUpdates(manual: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(l("Configuration", "设置"))
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
    
    private func checkForUpdates(manual: Bool = false, retryCount: Int = 3) {
        if manual { updateStatus = l("Checking...", "检查中...") }
        let url = URL(string: "https://api.github.com/repos/NalaniFlynns/IMUNavigator/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                DispatchQueue.main.async {
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    if tagName.contains(currentVersion) || currentVersion.contains(tagName) {
                        if manual { self.updateStatus = l("Up to date", "已是最新版本") }
                    } else {
                        self.updateStatus = l("New version available: ", "有新版本: ") + tagName
                    }
                }
            } else {
                if retryCount > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.checkForUpdates(manual: manual, retryCount: retryCount - 1)
                    }
                } else {
                    if manual {
                        DispatchQueue.main.async { self.updateStatus = l("Check failed, tap to retry", "检查失败，点击重试") }
                    }
                }
            }
        }.resume()
    }
}

// --- 赞赏页面 ---
struct SponsorView: View {
    @State private var showSaveToast = false
    @State private var sponsorImage: UIImage? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.pink)
                .padding(.top, 40)
            
            Text(l("Thank you for your support!", "感谢您的支持！"))
                .font(.title2)
                .bold()
            
            Text(l("IMUNavigator is an open-source project, your support helps maintain continuous development, model training and maintenance.", "IMUNavigator 是一款开源项目，您的赞赏将用于维持项目的持续开发、模型训练与维护。"))
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Group {
                if let image = sponsorImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView("Loading...")
                }
            }
            .frame(maxWidth: 250, minHeight: 250)
            .cornerRadius(12)
            .shadow(radius: 5)
            .padding(.vertical, 10)
            .contextMenu {
                Button {
                    if let image = sponsorImage {
                        ImageSaver.shared.writeToPhotoAlbum(image: image) {
                            DispatchQueue.main.async {
                                showSaveToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showSaveToast = false
                                }
                            }
                        }
                    }
                } label: {
                    Label(l("Save QR Code", "保存赞赏码"), systemImage: "square.and.arrow.down")
                }
            }
            
            if showSaveToast {
                Text(l("✅ QR Code saved to album", "✅ 赞赏码已保存到相册"))
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            } else {
                Text(l("Long press to save, or screenshot to scan in WeChat/Alipay", "长按图片可保存，或截图保存在微信/支付宝中扫一扫"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .navigationTitle("Buy me a coffee")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut, value: showSaveToast)
        .onAppear {
            loadSponsorImage()
        }
    }
    
    private func loadSponsorImage(retryCount: Int = 3) {
        if let cached = ImageCache.shared.cache["sponsor"] {
            self.sponsorImage = cached
            return
        }
        
        let urlStr = "https://raw.githubusercontent.com/NalaniFlynns/IMUNavigator/main/IMUNavigator/Assets.xcassets/SponsorCode.imageset/sponsor.jpg"
        guard let url = URL(string: urlStr) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    ImageCache.shared.cache["sponsor"] = image
                    self.sponsorImage = image
                }
            } else if retryCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.loadSponsorImage(retryCount: retryCount - 1)
                }
            }
        }.resume()
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
            UIKitSegmentedPicker(selection: $tab, items: [l("Sensors", "传感器"), l("ML Info", "ML 信息"), l("App Logs", "应用日志")])
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
        .navigationTitle(l("System Debug Console", "系统调试控制台"))
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

struct ChartToggle: View {
    var title: String
    var color: Color
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundColor(isOn ? color : .gray)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct MLInfoTabView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    @State private var tick = 0
    
    @State private var chartModeIndex: Int = 1
    @State private var timeRangeMode: Int = 1
    @State private var timeWindowDuration: Double = 30.0
    @State private var chartScaleLevel: Int = 1
    
    @State private var showAccX: Bool = true
    @State private var showAccY: Bool = true
    @State private var showSpeed: Bool = true
    @State private var showResX: Bool = true
    @State private var showResY: Bool = true
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(icon: "cpu", title: l("NR Mode Status", "NR 模式状态"), value: engine.debugState.mlStatus)
            DebugRow(icon: "move.3d", title: l("NR Predicted Vel", "NR 预测速度"), value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
            DebugRow(icon: "bolt.badge.clock", title: l("NR Processing FPS", "NR 处理帧率"), value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text(l("Chart Configuration", "图表配置")).font(.headline).foregroundColor(.primary)
                
                UIKitSegmentedPicker(selection: $chartModeIndex, items: [l("IMU vs ML", "IMU 与 ML 对比"), l("NR vs AR", "NR 与 AR 对比")])
                    .frame(height: 32)
                
                UIKitSegmentedPicker(selection: $timeRangeMode, items: [l("Global History", "全局历史"), l("Time Window", "时间窗口")])
                    .frame(height: 32)
                
                if timeRangeMode == 1 {
                    HStack {
                        Text("\(l("Window:", "窗口:")) \(Int(timeWindowDuration))s").font(.subheadline).frame(width: 90, alignment: .leading)
                        UIKitSlider(value: $timeWindowDuration, range: 1.0...300.0)
                    }
                }
                
                HStack {
                    Text(l("Precision Scale:", "精度缩放:")).font(.subheadline).frame(width: 120, alignment: .leading)
                    UIKitSegmentedPicker(selection: $chartScaleLevel, items: [l("Coarse", "粗略"), l("Normal", "正常"), l("Fine", "精细")])
                        .frame(height: 32)
                }
            }
            .padding(.bottom, 5)
            
            let allPoints = engine.chartPoints
            let baseTime = allPoints.first?.timestamp ?? 0
            let maxTime = allPoints.last?.timestamp ?? 0
            
            let minTime = timeRangeMode == 0 ? baseTime : max(baseTime, maxTime - timeWindowDuration)
            
            var displayPoints: [TrackingPoint] = []
            if timeRangeMode == 0 {
                displayPoints = allPoints
            } else {
                if let firstVisibleIndex = allPoints.firstIndex(where: { $0.timestamp >= minTime }) {
                    let startIndex = max(0, firstVisibleIndex - 1)
                    displayPoints = Array(allPoints[startIndex...])
                } else {
                    displayPoints = []
                }
            }
            
            let domainMin = minTime - baseTime
            let domainMax = max(domainMin + 1.0, maxTime - baseTime)
            
            let chartHeight: CGFloat = chartScaleLevel == 0 ? 100 : (chartScaleLevel == 1 ? 160 : 260)
            
            if chartModeIndex == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ChartToggle(title: "Acc X", color: .green, isOn: $showAccX)
                        ChartToggle(title: "Acc Y", color: .yellow, isOn: $showAccY)
                        ChartToggle(title: "ML Speed", color: .purple, isOn: $showSpeed)
                    }
                }
                .padding(.bottom, 5)
                
                let accX = engine.debugState.correctedAcc.x
                let accY = engine.debugState.correctedAcc.y
                let mlSpeed = hypot(engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y)
                
                let avgAccX = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.x }.reduce(0, +) / Double(displayPoints.count)
                let avgAccY = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.y }.reduce(0, +) / Double(displayPoints.count)
                let avgSpeed = displayPoints.isEmpty ? 0 : displayPoints.map { $0.speed }.reduce(0, +) / Double(displayPoints.count)
                
                var minValues: [Double] = []
                var maxValues: [Double] = []
                if showAccX {
                    minValues.append(displayPoints.compactMap { $0.acceleration?.x }.min() ?? 0)
                    maxValues.append(displayPoints.compactMap { $0.acceleration?.x }.max() ?? 0)
                }
                if showAccY {
                    minValues.append(displayPoints.compactMap { $0.acceleration?.y }.min() ?? 0)
                    maxValues.append(displayPoints.compactMap { $0.acceleration?.y }.max() ?? 0)
                }
                if showSpeed {
                    minValues.append(displayPoints.map { $0.speed }.min() ?? 0)
                    maxValues.append(displayPoints.map { $0.speed }.max() ?? 0)
                }
                
                let chart1Min = minValues.min() ?? 0
                let chart1Max = maxValues.max() ?? 0
                let c1Span = max(chart1Max - chart1Min, 0.01)
                let c1Domain = (chart1Min - c1Span * 0.1)...(chart1Max + c1Span * 0.1)
                
                DebugRow(icon: "waveform.path", title: "IMU Accel X", value: String(format: "%.3f (Avg: %.3f)", accX, avgAccX))
                    .foregroundColor(showAccX ? .green : .gray.opacity(0.5))
                DebugRow(icon: "waveform.path", title: "IMU Accel Y", value: String(format: "%.3f (Avg: %.3f)", accY, avgAccY))
                    .foregroundColor(showAccY ? .yellow : .gray.opacity(0.5))
                DebugRow(icon: "speedometer", title: "ML Output Speed", value: String(format: "%.3f (Avg: %.3f)", mlSpeed, avgSpeed))
                    .foregroundColor(showSpeed ? .purple : .gray.opacity(0.5))
                
                if !engine.chartPoints.isEmpty {
                    Chart {
                        ForEach(displayPoints) { point in
                            let time = point.timestamp - baseTime
                            
                            if showAccX {
                                LineMark(
                                    x: .value("Time", time),
                                    y: .value("Value", point.acceleration?.x ?? 0.0)
                                )
                                .foregroundStyle(by: .value("Metric", "Acc X"))
                            }
                            
                            if showAccY {
                                LineMark(
                                    x: .value("Time", time),
                                    y: .value("Value", point.acceleration?.y ?? 0.0)
                                )
                                .foregroundStyle(by: .value("Metric", "Acc Y"))
                            }
                            
                            if showSpeed {
                                LineMark(
                                    x: .value("Time", time),
                                    y: .value("Value", point.speed)
                                )
                                .foregroundStyle(by: .value("Metric", "ML Speed"))
                            }
                        }
                        
                        if showAccX {
                            RuleMark(y: .value("Avg Acc X", avgAccX))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                        if showAccY {
                            RuleMark(y: .value("Avg Acc Y", avgAccY))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(.yellow.opacity(0.8))
                        }
                        if showSpeed {
                            RuleMark(y: .value("Avg Speed", avgSpeed))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(.purple.opacity(0.8))
                        }
                    }
                    .chartForegroundStyleScale([
                        "Acc X": .green,
                        "Acc Y": .yellow,
                        "ML Speed": .purple
                    ])
                    .chartXScale(domain: domainMin...domainMax)
                    .chartYScale(domain: c1Domain)
                    .chartXAxis(.hidden)
                    .frame(height: chartHeight)
                }
                
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ChartToggle(title: "X Res", color: .blue, isOn: $showResX)
                        ChartToggle(title: "Y Res", color: .red, isOn: $showResY)
                    }
                }
                .padding(.bottom, 5)
                
                let xRes = engine.chartPoints.last?.resX ?? 0.0
                let yRes = engine.chartPoints.last?.resY ?? 0.0
                
                let avgXRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resX }.reduce(0, +) / Double(displayPoints.count)
                let avgYRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resY }.reduce(0, +) / Double(displayPoints.count)
                
                var minValues2: [Double] = []
                var maxValues2: [Double] = []
                if showResX {
                    minValues2.append(displayPoints.compactMap { $0.resX }.min() ?? 0)
                    maxValues2.append(displayPoints.compactMap { $0.resX }.max() ?? 0)
                }
                if showResY {
                    minValues2.append(displayPoints.compactMap { $0.resY }.min() ?? 0)
                    maxValues2.append(displayPoints.compactMap { $0.resY }.max() ?? 0)
                }
                
                let chart2Min = minValues2.min() ?? 0
                let chart2Max = maxValues2.max() ?? 0
                let c2Span = max(chart2Max - chart2Min, 0.01)
                let c2Domain = (chart2Min - c2Span * 0.1)...(chart2Max + c2Span * 0.1)
                
                DebugRow(icon: "arrow.left.and.right", title: "X-Axis Residual", value: String(format: "%.3f m (Avg: %.3f)", xRes, avgXRes))
                    .foregroundColor(showResX ? .blue : .gray.opacity(0.5))
                DebugRow(icon: "arrow.up.and.down", title: "Y-Axis Residual", value: String(format: "%.3f m (Avg: %.3f)", yRes, avgYRes))
                    .foregroundColor(showResY ? .red : .gray.opacity(0.5))
                
                if !engine.chartPoints.isEmpty {
                    Chart {
                        ForEach(displayPoints) { point in
                            let time = point.timestamp - baseTime
                            
                            if showResX {
                                LineMark(
                                    x: .value("Time", time),
                                    y: .value("Error", point.resX ?? 0.0)
                                )
                                .foregroundStyle(by: .value("Axis", "X Res"))
                            }
                            if showResY {
                                LineMark(
                                    x: .value("Time", time),
                                    y: .value("Error", point.resY ?? 0.0)
                                )
                                .foregroundStyle(by: .value("Axis", "Y Res"))
                            }
                        }
                        
                        if showResX {
                            RuleMark(y: .value("Avg X", avgXRes))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(.blue.opacity(0.8))
                        }
                        if showResY {
                            RuleMark(y: .value("Avg Y", avgYRes))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    .chartForegroundStyleScale([
                        "X Res": .blue,
                        "Y Res": .red
                    ])
                    .chartXScale(domain: domainMin...domainMax)
                    .chartYScale(domain: c2Domain)
                    .chartXAxis(.hidden)
                    .frame(height: chartHeight)
                }
            }
            
            Text(l("Model Expects: [1, 6, 200] Float32/Double Array\n100Hz Hardware -> 200Hz Lerp Resampling", "模型期望: [1, 6, 200] Float32/Double 数组\n100Hz 硬件采集 -> 200Hz 线性插值重采样"))
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
    @State private var selectedLevelIndex: Int = 0
    let levels: [LogLevel] = [.debug, .info, .warning, .error]
    
    var filteredLogs: [LogEntry] {
        logger.logs.filter { $0.level >= levels[selectedLevelIndex] }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l("Level Filter:", "日志等级:"))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                UIKitSegmentedPicker(
                    selection: $selectedLevelIndex,
                    items: levels.map { $0.rawValue }
                )
                .frame(height: 32)
            }
            .padding(.bottom, 4)
            
            ForEach(filteredLogs) { log in
                Text(log.formattedString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(log.level.color)
                    .textSelection(.enabled) 
                    .contextMenu { 
                        Button {
                            UIPasteboard.general.string = log.formattedString
                        } label: {
                            Label(l("Copy Log", "复制日志"), systemImage: "doc.on.doc")
                        }
                    }
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
