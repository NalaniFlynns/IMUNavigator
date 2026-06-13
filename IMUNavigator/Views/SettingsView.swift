import Foundation
import ARKit
import CoreMotion
import CoreLocation
import ActivityKit
import simd
import Combine
import SwiftUI

public struct RenderBounds {
    var center: CGPoint = .zero
    var maxRange: CGFloat = 1.0
    var minZ: Double = 0.0
    var maxZ: Double = 0.0
}

struct SystemDebugState {
    var rawAcc: simd_double3 = .zero
    var rawGyro: simd_double3 = .zero
    var compassHeading: Double = 0
    var baroAlt: Double = 0.0
    var correctedAcc: simd_double3 = .zero
    var arkitState: String = "N/A"
    var arkitPos: simd_double3 = .zero
    var mlStatus: String = "Waiting..."
    var mlVelocity: simd_double2 = .zero
    var imuFPS: Double = 0.0
    var mlFPS: Double = 0.0
}

// --- 日志等级与结构体 ---
enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warning: 2, .error: 3]
        return order[lhs]! < order[rhs]!
    }
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct LogEntry: Hashable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    var formattedString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: timestamp))] [\(level.rawValue)] \(message)"
    }
}

class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published var logs: [LogEntry] = []
    
    // 增加 level 参数，默认 INFO，兼容之前的代码调用
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.logs.insert(entry, at: 0)
            if self.logs.count > 500 { self.logs.removeLast() }
        }
        print(entry.formattedString)
    }
}

class SensorFusionEngine: NSObject, ObservableObject, ARSessionDelegate, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var renderPoints: [TrackingPoint] = []; @Published var chartPoints: [TrackingPoint] = []
    @Published var renderBounds: RenderBounds = RenderBounds()
    @Published var pureARPoints: [TrackingPoint] = []; @Published var pureBlindPoints: [TrackingPoint] = []
    
    @Published var windowAR: [(TimeInterval, simd_double3)] = []; @Published var windowBlind: [(TimeInterval, simd_double3)] = []
    
    @Published var currentPoint: TrackingPoint?
    @Published var totalDistance: Double = 0.0; @Published var currentSpeed: Double = 0.0
    @Published var cumulativeError: Double = 0.0; @Published var currentResidual: Double = 0.0
    @Published var currentAccResidual: Double = 0.0
    
    @Published var currentResX: Double = 0.0
    @Published var currentResY: Double = 0.0
    
    @Published var statusText: String = "Ready"; @Published var memorySizeText: String = "0 KB"
    
    @Published var activeEngine: String = "Initializing"
    @Published var navState: String = "Initializing"
    @Published var motionStateStr: String = "Unknown"
    @Published var slamConfidence: String = "N/A"
    @Published var sensorStatus: String = "Gyro/Mag Init"
    @Published var isZUPTActive: Bool = false
    @Published var autoAlignValueDisplay: Double = 0.0
    
    @Published var liveEarthAcc = simd_double3(0,0,0)
    @Published var isCalibrating = false
    @Published var calibrationProgress: Double = 0.0
    
    @Published var debugState = SystemDebugState()
    
    private var dbPoints: [TrackingPoint] = []
    private var actualDataBytes: Int = 0
    
    private let arSession = ARSession(); private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager(); private let pedometer = CMPedometer()
    private let locationManager = CLLocationManager(); private let altimeter = CMAltimeter()
    private let bleScanner = BluetoothScanner()
    private var liveActivity: Activity<INSActivityAttributes>?
    
    private var globalPosition = simd_double3(0, 0, 0)
    private var currentVelocity = simd_double3(0, 0, 0)
    private var currentAccBias = simd_double3(0, 0, 0)
    private var fusedHeading: Double = 0.0
    
    private var slamOffset = simd_double3(0, 0, 0)
    private var wasImuOnly = true
    private var lastImuTimestamp: TimeInterval = 0; private var lastSlamTimestamp: TimeInterval = 0
    private var lastAlignedSlamPos = simd_double3(0, 0, 0)
    private var smoothedARVelocity = simd_double3(0, 0, 0)
    private var lastRawSlamVel = simd_double3(0, 0, 0)
    
    private var lastDeviceAcc = simd_double3(0,0,0); private var lastDeviceGyro = simd_double3(0,0,0)
    private var sessionMetadata: SessionMetadata?
    private var firstPoint: TrackingPoint?; private var lastRenderedPoint: TrackingPoint?
    private var pointCounter: Int = 1
    
    private var currentGNSS: CLLocation?; private var currentHeading: Double = 0
    private var currentBaroAlt: Double? = nil; private var initialBaroAlt: Double? = nil
    private var lastValidBaroAlt: Double = 0.0
    private var isInBackground = false; private var slamIsValid = false
    private var zuptCounter: Int = 0
    
    private var currentActivity: CMMotionActivity?; private var lastPedometerDistance: Double = 0.0; private var currentPedometerDelta: Double = 0.0
    private var latestMLVelocity: simd_double2? = nil; private var lastMLPredictTime: TimeInterval = 0
    
    private var alignWindowAR: [(TimeInterval, simd_double3)] = []; private var alignWindowBlind: [(TimeInterval, simd_double3)] = []
    private var currentBlindPosWithoutOffset = simd_double3(0,0,0)
    
    private var calibrationStartTime: TimeInterval = 0; private var calibrationSamples = 0
    private var tempAccBiasSum = simd_double3(0,0,0); private var calibrationCompletionBlock: (() -> Void)? = nil
    
    private let engineQueue = DispatchQueue(label: "com.imu.engine", qos: .userInteractive)
    private let renderQueue = DispatchQueue(label: "com.imu.render", qos: .default)
    private var localRenderPoints: [TrackingPoint] = []; private var lastUIRefreshTime: TimeInterval = 0; private var lastActivityUpdateTime: TimeInterval = 0
    
    private var recentErrors: [(TimeInterval, Double)] = []
    private var recentResiduals: [(TimeInterval, Double)] = []
    private var recentAccErrors: [(TimeInterval, Double)] = []
    private var imuFrameCount = 0; private var lastFPSTime: TimeInterval = 0
    private var mlFrameCount = 0; private var lastMLFPSTime: TimeInterval = 0
    
    override init() {
        super.init()
        arSession.delegate = self; locationManager.delegate = self
        locationManager.requestAlwaysAuthorization(); locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = true; locationManager.pausesLocationUpdatesAutomatically = false
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        AppLogger.shared.log("System Initialized.", level: .info)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 200.0
            motionManager.showsDeviceMovementDisplay = true
            motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue()) { [weak self] data, error in
                guard let data = data, let self = self else { return }
                self.processEngineCascade(data: data)
            }
        }
    }
    
    func startRecording() {
        UIApplication.shared.isIdleTimerDisabled = true
        engineQueue.async { [weak self] in guard let self = self else { return }
            AppLogger.shared.log("Session Started. Mode: \(AppSettings.shared.coreNavMode.rawValue)", level: .info)
            DispatchQueue.main.async {
                self.isRecording = true; self.dbPoints.removeAll(); self.renderPoints.removeAll(); self.chartPoints.removeAll()
                self.pureARPoints.removeAll(); self.pureBlindPoints.removeAll(); self.windowAR.removeAll(); self.windowBlind.removeAll()
                self.recentErrors.removeAll(); self.recentResiduals.removeAll(); self.recentAccErrors.removeAll()
                self.totalDistance = 0.0; self.cumulativeError = 0.0; self.currentResidual = 0.0; self.currentAccResidual = 0.0
                
                self.currentResX = 0.0; self.currentResY = 0.0
                
                self.actualDataBytes = 0
                self.globalPosition = simd_double3(0,0,0); self.currentVelocity = simd_double3(0,0,0); self.smoothedARVelocity = simd_double3(0,0,0); self.lastRawSlamVel = simd_double3(0,0,0)
                self.currentAccBias = simd_double3(AppSettings.shared.manualBiasX, AppSettings.shared.manualBiasY, AppSettings.shared.manualBiasZ)
                self.slamOffset = simd_double3(0,0,0); self.currentBlindPosWithoutOffset = simd_double3(0,0,0)
                self.wasImuOnly = true; self.firstPoint = nil; self.lastRenderedPoint = nil; self.pointCounter = 1; self.zuptCounter = 0
                self.localRenderPoints.removeAll(); self.alignWindowAR.removeAll(); self.alignWindowBlind.removeAll(); self.initialBaroAlt = nil
                self.navState = "Initializing"
                self.startLiveActivity()
            }
            
            self.locationManager.startUpdatingLocation(); self.locationManager.startUpdatingHeading(); self.bleScanner.startScanning()
            if CMAltimeter.isRelativeAltitudeAvailable() { self.altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, _ in self.currentBaroAlt = data?.relativeAltitude.doubleValue } }
            if CMMotionActivityManager.isActivityAvailable() { self.activityManager.startActivityUpdates(to: .main) { act in self.currentActivity = act } }
            if CMPedometer.isStepCountingAvailable() { self.pedometer.startUpdates(from: Date()) { data, _ in if let d = data?.distance?.doubleValue { self.engineQueue.async { let delta = d - self.lastPedometerDistance; self.currentPedometerDelta += delta; self.lastPedometerDistance = d } } } }
            
            self.sessionMetadata = SessionMetadata(startTime: Date(), recordingMode: AppSettings.shared.recordingMode.rawValue, timeInterval: AppSettings.shared.recordIntervalTime, spaceInterval: AppSettings.shared.recordIntervalSpace, initialLatitude: self.currentGNSS?.coordinate.latitude, initialLongitude: self.currentGNSS?.coordinate.longitude, initialBarometerAlt: self.currentBaroAlt)
            
            if !self.isInBackground && AppSettings.shared.coreNavMode == .fusion { let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravityAndHeading; self.arSession.run(config, options: [.resetTracking]); DispatchQueue.main.async { self.statusText = "Active" } }
            else { DispatchQueue.main.async { self.statusText = "Active (Blind)" } }
        }
    }
    
    func stopRecording() {
        UIApplication.shared.isIdleTimerDisabled = false
        engineQueue.async { [weak self] in guard let self = self else { return }
            AppLogger.shared.log("Session Stopped.", level: .info)
            self.arSession.pause(); self.locationManager.stopUpdatingLocation(); self.locationManager.stopUpdatingHeading(); self.altimeter.stopRelativeAltitudeUpdates(); self.bleScanner.stopScanning()
            self.activityManager.stopActivityUpdates(); self.pedometer.stopUpdates()
            self.saveSessionData(); self.stopLiveActivity()
            DispatchQueue.main.async { self.isRecording = false; self.statusText = "Stopped"; self.activeEngine = "Stopped"; self.navState = "Stopped" }
        }
    }
    
    func switchNavMode(to mode: CoreNavMode) { guard isRecording else { return }; engineQueue.async { AppLogger.shared.log("Switched to \(mode.rawValue)", level: .info); if mode == .fusion && !self.isInBackground { self.wasImuOnly = true; let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravityAndHeading; self.arSession.run(config, options: [.resetTracking]); DispatchQueue.main.async { self.statusText = "Active" } } else { self.arSession.pause(); DispatchQueue.main.async { self.statusText = "Active (Blind)" } } } }
    
    func triggerManualCalibration(completion: @escaping () -> Void) { engineQueue.async { AppLogger.shared.log("Calibration Started...", level: .debug); self.tempAccBiasSum = simd_double3(0,0,0); self.calibrationSamples = 0; self.calibrationStartTime = 0; DispatchQueue.main.async { self.calibrationCompletionBlock = completion; self.isCalibrating = true; self.calibrationProgress = 0.0 } } }
    
    @objc private func appDidEnterBackground() { if !AppSettings.shared.enableBackgroundRecording { stopRecording(); return }; isInBackground = true; arSession.pause(); AppLogger.shared.log("Entered Background", level: .warning); DispatchQueue.main.async { self.statusText = "Background" } }
    @objc private func appWillEnterForeground() { if !isRecording { return }; isInBackground = false; AppLogger.shared.log("Entered Foreground", level: .info); if AppSettings.shared.coreNavMode == .fusion { let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravityAndHeading; arSession.run(config, options: []) }; DispatchQueue.main.async { self.statusText = "Active" } }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording, !isInBackground, AppSettings.shared.coreNavMode == .fusion else { return }
        engineQueue.async { [weak self] in guard let self = self else { return }
            let mode = AppSettings.shared.slamFilterMode; var isValid = false; var confStr = "Unknown"
            switch frame.camera.trackingState { case .normal: confStr = "Normal"; isValid = true; case .limited(let reason): confStr = "Limited(\(reason))"; isValid = (mode == .off || mode == .moderate); case .notAvailable: confStr = "N/A"; isValid = (mode == .off) }
            
            DispatchQueue.main.async { self.slamConfidence = confStr; self.slamIsValid = isValid; self.debugState.arkitState = confStr }
            
            if isValid {
                let t = frame.camera.transform; let rawSlamPos = simd_double3(Double(t.columns.3.x), Double(-t.columns.3.z), Double(t.columns.3.y))
                DispatchQueue.main.async { self.debugState.arkitPos = rawSlamPos }
                
                let nowTime = Date().timeIntervalSince1970
                self.alignWindowAR.append((nowTime, rawSlamPos))
                self.alignWindowAR.removeAll(where: { nowTime - $0.0 > 5.0 })
                
                if self.wasImuOnly { 
                    self.slamOffset = self.globalPosition - rawSlamPos; self.wasImuOnly = false; 
                    self.lastAlignedSlamPos = rawSlamPos + self.slamOffset; self.lastSlamTimestamp = frame.timestamp; 
                    AppLogger.shared.log("VIO Resumed & Offset Aligned.", level: .info)
                    return 
                }
                
                var alignedSlamPos = rawSlamPos + self.slamOffset
                let dtSlam = self.lastSlamTimestamp > 0 ? (frame.timestamp - self.lastSlamTimestamp) : 0.016
                
                if dtSlam > 0 {
                    var rawSlamVel = (alignedSlamPos - self.lastAlignedSlamPos) / dtSlam
                    
                    let acceleration = length(rawSlamVel - self.lastRawSlamVel) / dtSlam
                    let isJump = acceleration > 25.0 || length(rawSlamVel) > 15.0
                    
                    if !AppSettings.shared.enableSLAMCorrection && isJump {
                        let expectedPos = self.lastAlignedSlamPos + self.smoothedARVelocity * dtSlam
                        self.slamOffset = expectedPos - rawSlamPos
                        
                        alignedSlamPos = rawSlamPos + self.slamOffset
                        rawSlamVel = (alignedSlamPos - self.lastAlignedSlamPos) / dtSlam
                    }
                    
                    self.smoothedARVelocity = 0.8 * self.smoothedARVelocity + 0.2 * rawSlamVel
                    let deltaV = self.smoothedARVelocity - self.currentVelocity
                    
                    let slamAcc = (rawSlamVel - self.lastRawSlamVel) / dtSlam
                    self.lastRawSlamVel = rawSlamVel
                    
                    let imuAccGlobal = self.debugState.correctedAcc
                    let accDiff = length(slamAcc - imuAccGlobal)
                    
                    self.recentAccErrors.append((nowTime, accDiff))
                    self.recentAccErrors.removeAll(where: { nowTime - $0.0 > 1.0 })
                    let accResidual1s = self.recentAccErrors.map { $0.1 }.reduce(0, +) / Double(max(1, self.recentAccErrors.count))
                    
                    DispatchQueue.main.async {
                        self.currentResidual = length(deltaV)
                        self.currentAccResidual = accResidual1s
                        self.currentResX = deltaV.x
                        self.currentResY = deltaV.y
                    }
                    
                    if AppSettings.shared.enableDynamicCalibration {
                        let gain = 0.0005
                        let newBiasX = AppSettings.shared.manualBiasX - gain * deltaV.x / dtSlam
                        let newBiasY = AppSettings.shared.manualBiasY - gain * deltaV.y / dtSlam
                        let newBiasZ = AppSettings.shared.manualBiasZ - gain * deltaV.z / dtSlam
                        DispatchQueue.main.async { AppSettings.shared.manualBiasX = newBiasX; AppSettings.shared.manualBiasY = newBiasY; AppSettings.shared.manualBiasZ = newBiasZ }
                    }
                    
                    self.globalPosition = alignedSlamPos
                    self.currentVelocity = self.smoothedARVelocity
                    
                    self.lastAlignedSlamPos = alignedSlamPos
                    self.lastSlamTimestamp = frame.timestamp
                    
                    self.evaluateAndSave(source: .arkitVIO, dt: dtSlam, accDevice: self.lastDeviceAcc, gyroDevice: self.lastDeviceGyro)
                }
            } else { self.wasImuOnly = true }
        }
    }
    
    private func processEngineCascade(data: CMDeviceMotion) {
        engineQueue.async { [weak self] in guard let self = self else { return }
            let dt = self.lastImuTimestamp > 0 ? (data.timestamp - self.lastImuTimestamp) : 0.01; self.lastImuTimestamp = data.timestamp
            let userAcc = data.userAcceleration; let rawAccDevice = simd_double3(userAcc.x, userAcc.y, userAcc.z)
            let gyro = data.rotationRate; let gyroDevice = simd_double3(gyro.x, gyro.y, gyro.z)
            self.lastDeviceAcc = rawAccDevice; self.lastDeviceGyro = gyroDevice
            
            self.imuFrameCount += 1
            let nowTime = Date().timeIntervalSince1970
            if nowTime - self.lastFPSTime >= 1.0 {
                let fps = Double(self.imuFrameCount) / (nowTime - self.lastFPSTime)
                DispatchQueue.main.async { self.debugState.imuFPS = fps }
                self.imuFrameCount = 0; self.lastFPSTime = nowTime
            }
            
            let q = data.attitude.quaternion; let quat = simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w)
            let a_cm = simd_act(quat.inverse, rawAccDevice); let g_cm = simd_act(quat.inverse, gyroDevice)
            let rawEarthAcc = simd_double3(-a_cm.y, a_cm.x, a_cm.z) * 9.81
            let rawEarthGyro = simd_double3(-g_cm.y, g_cm.x, g_cm.z)
            
            DispatchQueue.main.async {
                self.liveEarthAcc = rawEarthAcc
                self.debugState.rawAcc = rawEarthAcc
                self.debugState.rawGyro = rawEarthGyro
                self.debugState.compassHeading = data.heading
                self.debugState.baroAlt = self.currentBaroAlt ?? 0.0
            }
            
            if self.isCalibrating {
                if self.calibrationStartTime == 0 { self.calibrationStartTime = data.timestamp }
                let elapsed = data.timestamp - self.calibrationStartTime
                self.tempAccBiasSum += rawEarthAcc; self.calibrationSamples += 1
                DispatchQueue.main.async { self.calibrationProgress = min(elapsed / 5.0, 1.0) }
                if elapsed >= 5.0 {
                    let finalBias = self.tempAccBiasSum / Double(self.calibrationSamples)
                    DispatchQueue.main.async {
                        AppSettings.shared.manualBiasX = finalBias.x; AppSettings.shared.manualBiasY = finalBias.y; AppSettings.shared.manualBiasZ = finalBias.z
                        self.isCalibrating = false; self.calibrationCompletionBlock?(); self.calibrationCompletionBlock = nil
                        AppLogger.shared.log("Calibration Done: X:\(String(format:"%.3f",finalBias.x)) Y:\(String(format:"%.3f",finalBias.y))", level: .info)
                    }
                }
                return
            }
            
            let isPhysicallyStationary = (length(rawAccDevice) < AppSettings.shared.zuptThreshold) && (length(gyroDevice) < AppSettings.shared.zuptGyroThreshold)
            
            if AppSettings.shared.enableZUPT && isPhysicallyStationary {
                RoNINModelWrapper.shared.pushData(timestamp: data.timestamp, acc: .zero, gyro: .zero)
            } else {
                RoNINModelWrapper.shared.pushData(timestamp: data.timestamp, acc: rawAccDevice, gyro: gyroDevice)
            }
            
            var actStr = "Unknown"
            if let act = self.currentActivity { if act.walking { actStr = "Walking" } else if act.running { actStr = "Running" } else if act.automotive { actStr = "Automotive" } else if act.cycling { actStr = "Cycling" } else if act.stationary { actStr = "Stationary" } }
            
            if isPhysicallyStationary { actStr = "Stationary" }
            else if actStr == "Unknown" || actStr == "Stationary" {
                if self.currentPedometerDelta > 0 { actStr = "Walking" }
                else if length(self.currentVelocity) > 5.0 { actStr = "Automotive" }
                else { actStr = "Moving" }
            }
            
            let trueYawRad = data.attitude.yaw
            var magWeight = 0.02; if actStr == "Automotive" || data.magneticField.accuracy == .uncalibrated { magWeight = 0.001 }
            
            self.fusedHeading = (-trueYawRad * 180.0 / .pi).truncatingRemainder(dividingBy: 360)
            if self.fusedHeading < 0 { self.fusedHeading += 360 }
            
            DispatchQueue.main.async { self.motionStateStr = actStr; self.sensorStatus = (magWeight < 0.01) ? "Gyro Trusted (Mag Interfere)" : "Gyro/Mag Fused" }
            
            guard self.isRecording else { return }
            
            if AppSettings.shared.coreNavMode == .fusion && self.slamIsValid && !self.isInBackground { 
                self.currentPedometerDelta = 0 
                return 
            }
            
            self.wasImuOnly = true; var actEngine: TrackingSource = .imuFallback
            var dx_raw = 0.0; var dy_raw = 0.0; var vx_raw = 0.0; var vy_raw = 0.0
            
            let bias = simd_double3(AppSettings.shared.manualBiasX, AppSettings.shared.manualBiasY, AppSettings.shared.manualBiasZ)
            let correctedAcc = rawEarthAcc - bias
            DispatchQueue.main.async { self.debugState.correctedAcc = correctedAcc }
            
            let a_z = correctedAcc.z
            var v_z = self.currentVelocity.z + a_z * dt
            v_z *= 0.985
            var p_z = self.globalPosition.z + 0.5 * (self.currentVelocity.z + v_z) * dt
            
            if let baroAlt = self.currentBaroAlt, AppSettings.shared.recordBarometer {
                if self.initialBaroAlt == nil { self.initialBaroAlt = baroAlt }
                if let startAlt = self.initialBaroAlt {
                    let relativeBaro = baroAlt - startAlt
                    let baroVerticalSpeed = (relativeBaro - self.lastValidBaroAlt) / max(dt, 0.005)
                    let isLikelyPressurized = abs(baroVerticalSpeed) > 12.0 && actStr != "Running"
                    let baroGain = isLikelyPressurized ? 0.0005 : 0.02
                    let baroDiff = relativeBaro - p_z
                    p_z += baroDiff * baroGain
                    v_z += baroDiff * baroGain * 0.5
                    self.lastValidBaroAlt = relativeBaro
                }
            }
            
            if actStr == "Stationary" || isPhysicallyStationary {
                self.currentVelocity.x *= AppSettings.shared.dampingX
                self.currentVelocity.y *= AppSettings.shared.dampingY
                dx_raw = 0; dy_raw = 0; vx_raw = 0; vy_raw = 0; v_z = 0; actEngine = .imuFallback
            }
            else if actStr == "Walking" || actStr == "Running" {
                if self.currentPedometerDelta > 0 {
                    let d = self.currentPedometerDelta; self.currentPedometerDelta = 0;
                    let hdgRad = data.heading * .pi / 180.0
                    dx_raw = d * sin(hdgRad); dy_raw = d * cos(hdgRad)
                    vx_raw = dx_raw/dt; vy_raw = dy_raw/dt; actEngine = .pedometerPDR
                } else {
                    self.currentVelocity.x *= 0.90
                    self.currentVelocity.y *= 0.90
                    vx_raw = self.currentVelocity.x; vy_raw = self.currentVelocity.y; actEngine = .pedometerPDR
                }
            } else {
                if data.timestamp - self.lastMLPredictTime >= 0.1 {
                    self.lastMLPredictTime = data.timestamp
                    RoNINModelWrapper.shared.predictVelocity(currentTime: data.timestamp) { [weak self] vel, msg in
                        guard let self = self else { return }
                        self.engineQueue.async {
                            self.mlFrameCount += 1
                            let nowML = Date().timeIntervalSince1970
                            if nowML - self.lastMLFPSTime >= 1.0 {
                                let mFps = Double(self.mlFrameCount) / (nowML - self.lastMLFPSTime)
                                DispatchQueue.main.async { self.debugState.mlFPS = mFps }
                                self.mlFrameCount = 0; self.lastMLFPSTime = nowML
                            }
                            if let v = vel { self.latestMLVelocity = v }
                        }
                        DispatchQueue.main.async { self.debugState.mlStatus = msg; if let v = vel { self.debugState.mlVelocity = v } }
                    }
                }
                if let mlVel = self.latestMLVelocity {
                    let vx_global = mlVel.x * cos(-trueYawRad) + mlVel.y * sin(-trueYawRad)
                    let vy_global = -mlVel.x * sin(-trueYawRad) + mlVel.y * cos(-trueYawRad)
                    
                    vx_raw = vx_global - AppSettings.shared.driftCompX
                    vy_raw = vy_global - AppSettings.shared.driftCompY
                    dx_raw = vx_raw * dt; dy_raw = vy_raw * dt; actEngine = .neuralNR
                } else {
                    let v_next_xy = simd_double2(self.currentVelocity.x, self.currentVelocity.y) + simd_double2(correctedAcc.x, correctedAcc.y) * dt
                    let damped_v_xy = v_next_xy * 0.985
                    dx_raw = 0.5 * (self.currentVelocity.x + damped_v_xy.x) * dt; dy_raw = 0.5 * (self.currentVelocity.y + damped_v_xy.y) * dt
                    vx_raw = damped_v_xy.x; vy_raw = damped_v_xy.y; actEngine = .imuFallback
                }
            }
            
            self.currentBlindPosWithoutOffset += simd_double3(dx_raw, dy_raw, p_z - self.globalPosition.z)
            self.alignWindowBlind.append((nowTime, self.currentBlindPosWithoutOffset))
            self.alignWindowBlind.removeAll(where: { nowTime - $0.0 > 5.0 })
            
            let yawRad = AppSettings.shared.imuYawOffset * .pi / 180.0; let cosY = cos(yawRad); let sinY = sin(yawRad)
            var mappedX = dx_raw * cosY - dy_raw * sinY; var mappedY = dx_raw * sinY + dy_raw * cosY
            if AppSettings.shared.imuMirrorX { mappedX = -mappedX }; if AppSettings.shared.imuMirrorY { mappedY = -mappedY }
            
            let finalDeltaPos = simd_double3(mappedX, mappedY, p_z - self.globalPosition.z)
            self.globalPosition += finalDeltaPos
            
            let mappedVx = vx_raw * cosY - vy_raw * sinY; let mappedVy = vx_raw * sinY + vy_raw * cosY
            self.currentVelocity = simd_double3(mappedVx, mappedVy, v_z)
            
            let arSpeed = length(simd_double2(self.smoothedARVelocity.x, self.smoothedARVelocity.y))
            let nrSpeed = length(simd_double2(vx_raw, vy_raw))
            
            if AppSettings.shared.enableAutoAlignment && arSpeed > 0.4 && nrSpeed > 0.4 {
                let arAng = atan2(self.smoothedARVelocity.y, self.smoothedARVelocity.x)
                let nrAng = atan2(vy_raw, vx_raw)
                var diff = (arAng - nrAng) * 180.0 / .pi
                while diff > 180 { diff -= 360 }
                while diff < -180 { diff += 360 }
            
                let newYaw = AppSettings.shared.imuYawOffset * 0.98 + diff * 0.02
                DispatchQueue.main.async {
                    AppSettings.shared.imuYawOffset = newYaw
                    self.autoAlignValueDisplay = diff
                }
            }
            self.evaluateAndSave(source: actEngine, dt: dt, accDevice: rawAccDevice, gyroDevice: gyroDevice)
        }
    }
    
    private func evaluateAndSave(source: TrackingSource, dt: TimeInterval, accDevice: simd_double3, gyroDevice: simd_double3) {
        let accMag = length(accDevice); let gyroMag = length(gyroDevice); var zuptActive = false
        if AppSettings.shared.enableZUPT {
            if accMag < AppSettings.shared.zuptThreshold && gyroMag < AppSettings.shared.zuptGyroThreshold {
                self.zuptCounter += 1
                if self.zuptCounter > 10 { self.currentVelocity = simd_double3(0,0,0); zuptActive = true }
            } else { self.zuptCounter = 0 }
        } else { self.zuptCounter = 0 }
        
        let speedMag = length(currentVelocity)
        var instErr = 0.0; var currentCumErr = self.cumulativeError
        if !zuptActive {
            switch source { case .arkitVIO: instErr = (speedMag * dt) * 0.005; case .pedometerPDR: instErr = (speedMag * dt) * 0.02; case .neuralNR: instErr = (speedMag * dt) * 0.05; case .imuFallback: instErr = (speedMag * dt * 0.08) + (0.5 * 0.05 * dt * dt) }
            currentCumErr += instErr
        }
        
        let now = Date().timeIntervalSince1970
        recentErrors.append((now, instErr))
        recentErrors.removeAll(where: { now - $0.0 > 1.0 })
        let err1s = recentErrors.map { $0.1 }.reduce(0, +)
        
        recentResiduals.append((now, currentResidual))
        recentResiduals.removeAll(where: { now - $0.0 > 1.0 })
        let residual1s = recentResiduals.map { $0.1 }.reduce(0, +) / Double(max(1, recentResiduals.count))
        
        DispatchQueue.main.async {
            self.cumulativeError = currentCumErr
            self.isZUPTActive = zuptActive
        }
        
        var stepDisp = 0.0; var hdgChange = 0.0; var distStart = 0.0; var bearingStart = 0.0
        if let last = dbPoints.last { stepDisp = length(simd_double3(globalPosition.x - last.x, globalPosition.y - last.y, globalPosition.z - last.z)); hdgChange = self.fusedHeading - last.heading; if hdgChange > 180 { hdgChange -= 360 } else if hdgChange < -180 { hdgChange += 360 } }
        if let first = firstPoint { distStart = length(simd_double3(globalPosition.x - first.x, globalPosition.y - first.y, globalPosition.z - first.z)); bearingStart = atan2(globalPosition.y - first.y, globalPosition.x - first.x) * 180 / .pi }
        
        let settings = AppSettings.shared
        
        let point = TrackingPoint(
            id: pointCounter, 
            timestamp: Date().timeIntervalSince1970, 
            source: source, 
            x: globalPosition.x, y: globalPosition.y, z: globalPosition.z, 
            speed: speedMag, 
            heading: self.fusedHeading, 
            stepDisplacement: stepDisp, 
            headingChange: hdgChange, 
            distanceFromStart: distStart, 
            bearingFromStart: bearingStart, 
            cumulativeError: currentCumErr, 
            instantaneousError: err1s, 
            residual: residual1s, 
            accResidual: currentAccResidual, 
            isZUPTActive: zuptActive, 
            slamConfidence: slamConfidence, 
            resX: self.currentResX,
            resY: self.currentResY,
            latitude: settings.recordGNSS ? currentGNSS?.coordinate.latitude : nil, 
            longitude: settings.recordGNSS ? currentGNSS?.coordinate.longitude : nil, 
            gnssAccuracy: settings.recordGNSS ? currentGNSS?.horizontalAccuracy : nil, 
            gnssAltitude: settings.recordGNSS ? currentGNSS?.altitude : nil, 
            barometerAltitude: settings.recordBarometer ? currentBaroAlt : nil, 
            acceleration: settings.recordAcceleration ? accDevice : nil, 
            rotationRate: settings.recordAcceleration ? gyroDevice : nil, 
            bleDevices: bleScanner.currentDevices
        )
        
        let navStateStr = zuptActive ? "ZUPT" : source.rawValue
        DispatchQueue.main.async { self.currentPoint = point; self.currentSpeed = speedMag; self.activeEngine = source.rawValue; self.navState = navStateStr; self.checkIntervalsAndSave(point: point) }
    }
    
    private func checkIntervalsAndSave(point: TrackingPoint) {
        var shouldSave = false; if firstPoint == nil { firstPoint = point }
        if let last = dbPoints.last {
            let mode = AppSettings.shared.recordingMode; let sDiff = point.stepDisplacement
            if point.isZUPTActive && last.isZUPTActive { return }
            if mode == .time { let tSetting = AppSettings.shared.recordIntervalTime; let tDiff = point.timestamp - last.timestamp; if tSetting <= 0 || tDiff >= tSetting { shouldSave = true; totalDistance += sDiff } }
            else { let sSetting = AppSettings.shared.recordIntervalSpace; if sSetting <= 0 || sDiff >= sSetting { shouldSave = true; totalDistance += sDiff } }
        } else { shouldSave = true }
        
        if shouldSave {
            if self.dbPoints.count > 500000 { self.dbPoints.removeFirst(1000) }
            dbPoints.append(point); pointCounter += 1
            
            let bytesPerPoint = MemoryLayout<TrackingPoint>.stride
            self.actualDataBytes += bytesPerPoint
            
            let copyAR = Array(self.alignWindowAR)
            let copyBlind = Array(self.alignWindowBlind)
            
            renderQueue.async { [weak self] in guard let self = self else { return }
                var updated = false
                if let lastRender = self.lastRenderedPoint { let dist = hypot(point.x - lastRender.x, point.y - lastRender.y); let ang = abs(point.heading - lastRender.heading); if dist > 0.2 || ang > 5.0 { self.localRenderPoints.append(point); self.lastRenderedPoint = point; updated = true } } else { self.localRenderPoints.append(point); self.lastRenderedPoint = point; updated = true }
                
                if point.source == .arkitVIO { DispatchQueue.main.async { self.pureARPoints.append(point); if self.pureARPoints.count > 200 { self.pureARPoints.removeFirst() } } }
                else { DispatchQueue.main.async { self.pureBlindPoints.append(point); if self.pureBlindPoints.count > 200 { self.pureBlindPoints.removeFirst() } } }
                
                let now = Date().timeIntervalSince1970
                if updated && (now - self.lastUIRefreshTime >= 0.1) {
                    self.lastUIRefreshTime = now
                    if self.localRenderPoints.count > 10000 { self.localRenderPoints.removeFirst(self.localRenderPoints.count - 10000) }
                    
                    let zs = self.localRenderPoints.map { $0.z }; let minZ = zs.min() ?? 0; let maxZ = zs.max() ?? 0
                    let carX = point.x; let carY = point.y; let maxDistFromCar = self.localRenderPoints.map { hypot($0.x - carX, $0.y - carY) }.max() ?? 1.0
                    let bounds = RenderBounds(center: CGPoint(x: carX, y: carY), maxRange: CGFloat(maxDistFromCar * 2.1), minZ: minZ, maxZ: maxZ)
                    let step = max(1, self.localRenderPoints.count / 200); let cPoints = stride(from: 0, to: self.localRenderPoints.count, by: step).map { self.localRenderPoints[$0] }
                    let copyRender = Array(self.localRenderPoints)
                    
                    DispatchQueue.main.async {
                        self.renderPoints = copyRender
                        self.renderBounds = bounds
                        self.chartPoints = cPoints
                        self.windowAR = copyAR
                        self.windowBlind = copyBlind
                    }
                }
                if self.dbPoints.count % 10 == 0 { let mem = String(format: "%.1f KB", Double(self.actualDataBytes) / 1024.0); DispatchQueue.main.async { self.memorySizeText = mem }; if now - self.lastActivityUpdateTime >= 1.0 { self.lastActivityUpdateTime = now; DispatchQueue.main.async { self.updateLiveActivity() } } }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { currentGNSS = locations.last }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) { currentHeading = newHeading.trueHeading }
    private func saveSessionData() { guard let meta = sessionMetadata else { return }; let session = TrackingSession(id: UUID(), metadata: meta, endTime: Date(), points: dbPoints, totalDistance: totalDistance); StorageManager.shared.saveSession(session, format: AppSettings.shared.storageFormat); AppLogger.shared.log("Session Saved.", level: .info) }
    private func startLiveActivity() { guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }; do { liveActivity = try Activity.request(attributes: INSActivityAttributes(sessionName: "INS"), content: ActivityContent(state: INSActivityAttributes.ContentState(distance: 0, speed: 0, statusText: "Starting", activeEngine: activeEngine, motionState: motionStateStr, isZUPT: false), staleDate: nil), pushType: nil) } catch {} }
    private func updateLiveActivity() { guard let act = liveActivity else { return }; Task { await act.update(ActivityContent(state: INSActivityAttributes.ContentState(distance: totalDistance, speed: currentSpeed, statusText: statusText, activeEngine: activeEngine, motionState: motionStateStr, isZUPT: isZUPTActive), staleDate: nil)) } }
    private func stopLiveActivity() { guard let act = liveActivity else { return }; Task { await act.end(ActivityContent(state: INSActivityAttributes.ContentState(distance: totalDistance, speed: 0, statusText: "Completed", activeEngine: "Stopped", motionState: "Stopped", isZUPT: true), staleDate: nil), dismissalPolicy: .default) } }
}

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
                
                // --- 关于与赞助模块 ---
                Section(header: Text("About & Support")) {
                    VStack(spacing: 12) {
                        HStack(spacing: 15) {
                            Image(systemName: "safari.fill")
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
                                Text("Version \(version) (Build \(build))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        Divider()
                        
                        Link(destination: URL(string: "https://github.com/nalaniflynns/imunavigator")!) {
                            HStack {
                                Image(systemName: "chevron.left.forward.slash")
                                    .frame(width: 24)
                                Text("GitHub Repository")
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
                                Image(systemName: "ladybug.fill")
                                    .frame(width: 24)
                                Text("Submit Feedback")
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
                                Image(systemName: "qrcode.viewfinder")
                                    .frame(width: 24)
                                    .foregroundColor(.orange)
                                Text("Support the Developer")
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.vertical, 4)
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

// --- 赞赏页面 ---
struct SponsorView: View {
    @State private var showCopyToast = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .padding(.top, 40)
            
            Text("💖 感谢您的支持！")
                .font(.title2)
                .bold()
            
            Text("IMUNavigator 是一款开源项目，您的赞赏将用于维持项目的持续开发、模型训练与维护。")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Image("SponsorCode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 250)
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding(.vertical, 10)
                .contextMenu {
                    Button {
                        if let image = UIImage(named: "SponsorCode") {
                            UIPasteboard.general.image = image
                            showCopyToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopyToast = false
                            }
                        }
                    } label: {
                        Label("复制赞赏码", systemImage: "doc.on.doc")
                    }
                }
            
            if showCopyToast {
                Text("✅ 赞赏码已复制到剪贴板")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            } else {
                Text("长按图片可复制，或截图保存在微信/支付宝中扫一扫")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .navigationTitle("Buy me a coffee")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut, value: showCopyToast)
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
    
    @State private var chartModeIndex: Int = 1
    @State private var timeRangeMode: Int = 1
    @State private var timeWindowDuration: Double = 30.0
    @State private var chartScaleLevel: Int = 1
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DebugRow(icon: "cpu", title: "NR Mode Status", value: engine.debugState.mlStatus)
            DebugRow(icon: "move.3d", title: "NR Predicted Vel", value: String(format: "(%.3f, %.3f) m/s", engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y))
            DebugRow(icon: "bolt.badge.clock.fill", title: "NR Processing FPS", value: String(format: "%.1f Hz", engine.debugState.mlFPS)).foregroundColor(.orange)
            
            Divider()
            
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
            
            let allPoints = engine.chartPoints
            let baseTime = allPoints.first?.timestamp ?? 0
            let maxTime = allPoints.last?.timestamp ?? 0
            
            let minTime = timeRangeMode == 0 ? baseTime : max(baseTime, maxTime - timeWindowDuration)
            let displayPoints = timeRangeMode == 0 ? allPoints : allPoints.filter { $0.timestamp >= minTime }
            
            let domainMin = minTime - baseTime
            let domainMax = max(domainMin + 1.0, maxTime - baseTime)
            
            let chartHeight: CGFloat = chartScaleLevel == 0 ? 100 : (chartScaleLevel == 1 ? 160 : 260)
            
            if chartModeIndex == 0 {
                let accX = engine.debugState.correctedAcc.x
                let accY = engine.debugState.correctedAcc.y
                let mlSpeed = hypot(engine.debugState.mlVelocity.x, engine.debugState.mlVelocity.y)
                
                let avgAccX = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.x }.reduce(0, +) / Double(displayPoints.count)
                let avgAccY = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.acceleration?.y }.reduce(0, +) / Double(displayPoints.count)
                let avgSpeed = displayPoints.isEmpty ? 0 : displayPoints.map { $0.speed }.reduce(0, +) / Double(displayPoints.count)
                
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
                let c1Span = max(chart1Max - chart1Min, 0.01)
                let c1Domain = (chart1Min - c1Span * 0.1)...(chart1Max + c1Span * 0.1)
                
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
                    .chartYScale(domain: c1Domain)
                    .chartXAxis(.hidden)
                    .frame(height: chartHeight)
                }
                
            } else {
                let xRes = engine.chartPoints.last?.resX ?? 0.0
                let yRes = engine.chartPoints.last?.resY ?? 0.0
                
                let avgXRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resX }.reduce(0, +) / Double(displayPoints.count)
                let avgYRes = displayPoints.isEmpty ? 0 : displayPoints.compactMap { $0.resY }.reduce(0, +) / Double(displayPoints.count)
                
                let chart2Min = min(
                    displayPoints.compactMap { $0.resX }.min() ?? 0,
                    displayPoints.compactMap { $0.resY }.min() ?? 0
                )
                let chart2Max = max(
                    displayPoints.compactMap { $0.resX }.max() ?? 0,
                    displayPoints.compactMap { $0.resY }.max() ?? 0
                )
                let c2Span = max(chart2Max - chart2Min, 0.01)
                let c2Domain = (chart2Min - c2Span * 0.1)...(chart2Max + c2Span * 0.1)
                
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
                    .chartYScale(domain: c2Domain)
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

// --- 日志查看页面 ---
struct AppLogsTabView: View {
    @ObservedObject var logger = AppLogger.shared
    @State private var selectedLevel: LogLevel = .debug
    
    var filteredLogs: [LogEntry] {
        logger.logs.filter { $0.level >= selectedLevel }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level Filter:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Picker("Level", selection: $selectedLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.bottom, 4)
            
            ForEach(filteredLogs) { log in
                Text(log.formattedString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(log.level.color)
                    .textSelection(.enabled) // 支持手动框选复制
                    .contextMenu { // 支持长按整行复制
                        Button {
                            UIPasteboard.general.string = log.formattedString
                        } label: {
                            Label("Copy Log", systemImage: "doc.on.doc")
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
