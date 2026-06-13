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

class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published var logs: [String] = []
    func log(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss.SSS"
        let msg = "[\(formatter.string(from: Date()))] \(message)"
        DispatchQueue.main.async {
            self.logs.insert(msg, at: 0)
            if self.logs.count > 500 { self.logs.removeLast() }
        }
        print(msg)
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
    
    // --- 新增：X轴与Y轴的独立残差状态 ---
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
        
        AppLogger.shared.log("System Initialized.")
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
            AppLogger.shared.log("Session Started. Mode: \(AppSettings.shared.coreNavMode.rawValue)")
            DispatchQueue.main.async {
                self.isRecording = true; self.dbPoints.removeAll(); self.renderPoints.removeAll(); self.chartPoints.removeAll()
                self.pureARPoints.removeAll(); self.pureBlindPoints.removeAll(); self.windowAR.removeAll(); self.windowBlind.removeAll()
                self.recentErrors.removeAll(); self.recentResiduals.removeAll(); self.recentAccErrors.removeAll()
                self.totalDistance = 0.0; self.cumulativeError = 0.0; self.currentResidual = 0.0; self.currentAccResidual = 0.0
                
                // --- 录制开始时重置 X/Y 轴残差 ---
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
            AppLogger.shared.log("Session Stopped.")
            self.arSession.pause(); self.locationManager.stopUpdatingLocation(); self.locationManager.stopUpdatingHeading(); self.altimeter.stopRelativeAltitudeUpdates(); self.bleScanner.stopScanning()
            self.activityManager.stopActivityUpdates(); self.pedometer.stopUpdates()
            self.saveSessionData(); self.stopLiveActivity()
            DispatchQueue.main.async { self.isRecording = false; self.statusText = "Stopped"; self.activeEngine = "Stopped"; self.navState = "Stopped" }
        }
    }
    
    func switchNavMode(to mode: CoreNavMode) { guard isRecording else { return }; engineQueue.async { AppLogger.shared.log("Switched to \(mode.rawValue)"); if mode == .fusion && !self.isInBackground { self.wasImuOnly = true; let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravityAndHeading; self.arSession.run(config, options: [.resetTracking]); DispatchQueue.main.async { self.statusText = "Active" } } else { self.arSession.pause(); DispatchQueue.main.async { self.statusText = "Active (Blind)" } } } }
    
    func triggerManualCalibration(completion: @escaping () -> Void) { engineQueue.async { AppLogger.shared.log("Calibration Started..."); self.tempAccBiasSum = simd_double3(0,0,0); self.calibrationSamples = 0; self.calibrationStartTime = 0; DispatchQueue.main.async { self.calibrationCompletionBlock = completion; self.isCalibrating = true; self.calibrationProgress = 0.0 } } }
    
    @objc private func appDidEnterBackground() { if !AppSettings.shared.enableBackgroundRecording { stopRecording(); return }; isInBackground = true; arSession.pause(); AppLogger.shared.log("Entered Background"); DispatchQueue.main.async { self.statusText = "Background" } }
    @objc private func appWillEnterForeground() { if !isRecording { return }; isInBackground = false; AppLogger.shared.log("Entered Foreground"); if AppSettings.shared.coreNavMode == .fusion { let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravityAndHeading; arSession.run(config, options: []) }; DispatchQueue.main.async { self.statusText = "Active" } }
    
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
                
                if self.wasImuOnly { self.slamOffset = self.globalPosition - rawSlamPos; self.wasImuOnly = false; self.lastAlignedSlamPos = rawSlamPos + self.slamOffset; self.lastSlamTimestamp = frame.timestamp; AppLogger.shared.log("VIO Resumed & Offset Aligned."); return }
                
                let alignedSlamPos = rawSlamPos + self.slamOffset; let dtSlam = self.lastSlamTimestamp > 0 ? (frame.timestamp - self.lastSlamTimestamp) : 0.016
                if dtSlam > 0 {
                    let rawSlamVel = (alignedSlamPos - self.lastAlignedSlamPos) / dtSlam
                    self.smoothedARVelocity = 0.8 * self.smoothedARVelocity + 0.2 * rawSlamVel
                    let deltaV = self.smoothedARVelocity - self.currentVelocity
                    
                    let slamAcc = (rawSlamVel - self.lastRawSlamVel) / dtSlam
                    self.lastRawSlamVel = rawSlamVel
                    
                    let imuAccGlobal = self.debugState.correctedAcc
                    let accDiff = length(slamAcc - imuAccGlobal)
                    
                    self.recentAccErrors.append((nowTime, accDiff))
                    self.recentAccErrors.removeAll(where: { nowTime - $0.0 > 1.0 })
                    let accResidual1s = self.recentAccErrors.map { $0.1 }.reduce(0, +) / Double(max(1, self.recentAccErrors.count))
                    
                    // --- 同步提取 X 和 Y 轴方向的残差 ---
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
                    
                    if AppSettings.shared.enableSLAMCorrection {
                        self.globalPosition = alignedSlamPos
                        self.currentVelocity = self.smoothedARVelocity
                    }
                    
                    self.lastAlignedSlamPos = alignedSlamPos; self.lastSlamTimestamp = frame.timestamp
                    if AppSettings.shared.enableSLAMCorrection {
                        self.evaluateAndSave(source: .arkitVIO, dt: dtSlam, accDevice: self.lastDeviceAcc, gyroDevice: self.lastDeviceGyro)
                    }
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
                        AppLogger.shared.log("Calibration Done: X:\(String(format:"%.3f",finalBias.x)) Y:\(String(format:"%.3f",finalBias.y))")
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
            if AppSettings.shared.coreNavMode == .fusion && self.slamIsValid && !self.isInBackground && AppSettings.shared.enableSLAMCorrection { self.currentPedometerDelta = 0; return }
            
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
            let nrSpeed = length(simd_double2(vx_raw, vy_raw)) // Unmapped NR Velocity
            
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
        
        // --- 核心修改：在实例化TrackingPoint时写入刚计算得到的 resX 和 resY ---
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
            resX: self.currentResX,    // <- 注入 X轴 残差
            resY: self.currentResY,    // <- 注入 Y轴 残差
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
    private func saveSessionData() { guard let meta = sessionMetadata else { return }; let session = TrackingSession(id: UUID(), metadata: meta, endTime: Date(), points: dbPoints, totalDistance: totalDistance); StorageManager.shared.saveSession(session, format: AppSettings.shared.storageFormat); AppLogger.shared.log("Session Saved.") }
    private func startLiveActivity() { guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }; do { liveActivity = try Activity.request(attributes: INSActivityAttributes(sessionName: "INS"), content: ActivityContent(state: INSActivityAttributes.ContentState(distance: 0, speed: 0, statusText: "Starting", activeEngine: activeEngine, motionState: motionStateStr, isZUPT: false), staleDate: nil), pushType: nil) } catch {} }
    private func updateLiveActivity() { guard let act = liveActivity else { return }; Task { await act.update(ActivityContent(state: INSActivityAttributes.ContentState(distance: totalDistance, speed: currentSpeed, statusText: statusText, activeEngine: activeEngine, motionState: motionStateStr, isZUPT: isZUPTActive), staleDate: nil)) } }
    private func stopLiveActivity() { guard let act = liveActivity else { return }; Task { await act.end(ActivityContent(state: INSActivityAttributes.ContentState(distance: totalDistance, speed: 0, statusText: "Completed", activeEngine: "Stopped", motionState: "Stopped", isZUPT: true), staleDate: nil), dismissalPolicy: .default) } }
}
