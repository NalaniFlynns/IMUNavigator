import Foundation
import CoreML
import simd

struct MLBufferData {
    let timestamp: TimeInterval
    let acc: simd_double3
    let gyro: simd_double3
}

class RoNINModelWrapper {
    static let shared = RoNINModelWrapper()
    private var model: MLModel?
    private var inputFeatureName: String = ""
    private var outputFeatureName: String = ""
    private var expectedDataType: MLMultiArrayDataType = .double // 动态探测输入类型
    
    private var buffer: [MLBufferData] = []
    private let mlQueue = DispatchQueue(label: "com.imu.mlqueue", qos: .userInitiated)
    
    init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            if let modelURL = Bundle.main.url(forResource: "RoNIN_Navigation", withExtension: "mlmodelc") {
                self.model = try MLModel(contentsOf: modelURL, configuration: config)
                if let modelDesc = self.model?.modelDescription {
                    self.inputFeatureName = modelDesc.inputDescriptionsByName.keys.first ?? "input"
                    self.outputFeatureName = modelDesc.outputDescriptionsByName.keys.first ?? "output"
                    
                    // 🌟 核心修复：动态探测模型需要的实际数据类型 (Float32 / Double)
                    if let inputConstraint = modelDesc.inputDescriptionsByName[self.inputFeatureName]?.multiArrayConstraint {
                        self.expectedDataType = inputConstraint.dataType
                    }
                    AppLogger.shared.log("ML Model Loaded. Input: \(inputFeatureName) (\(self.expectedDataType == .float32 ? "Float32" : "Double")), Output: \(outputFeatureName)")
                }
            } else {
                AppLogger.shared.log("ERROR: RoNIN_Navigation.mlmodelc not found!")
            }
        } catch {
            AppLogger.shared.log("ML Model Load Failed: \(error.localizedDescription)")
        }
    }
    
    func pushData(timestamp: TimeInterval, acc: simd_double3, gyro: simd_double3) {
        mlQueue.async {
            self.buffer.append(MLBufferData(timestamp: timestamp, acc: acc, gyro: gyro))
            if self.buffer.count > 300 { self.buffer.removeFirst(self.buffer.count - 300) }
        }
    }
    
    func predictVelocity(currentTime: TimeInterval, completion: @escaping (simd_double2?, String) -> Void) {
        mlQueue.async {
            guard let model = self.model, !self.inputFeatureName.isEmpty else {
                completion(nil, "Model not loaded"); return
            }
            let targetDuration: TimeInterval = 1.0
            let startTime = currentTime - targetDuration
            
            let validData = self.buffer.filter { $0.timestamp >= startTime && $0.timestamp <= currentTime }
            guard validData.count > 50 else {
                completion(nil, "Data shortage (\(validData.count)/200)"); return
            }
            
            // 🌟 核心修复：使用模型真正要求的 dataType 初始化，防止 prediction 静默崩溃！
            guard let inputArray = try? MLMultiArray(shape: [1, 6, 200], dataType: self.expectedDataType) else {
                completion(nil, "Array init failed"); return
            }
            
            for i in 0..<200 {
                let tTarget = startTime + (Double(i) / 199.0) * targetDuration
                if let rIdx = validData.firstIndex(where: { $0.timestamp >= tTarget }) {
                    let lIdx = max(0, rIdx - 1)
                    let left = validData[lIdx]; let right = validData[rIdx]
                    let weight = (right.timestamp == left.timestamp) ? 0 : (tTarget - left.timestamp) / (right.timestamp - left.timestamp)
                    
                    // NSNumber 会自动桥接到 MLMultiArray 的底层 DataType
                    inputArray[[0, 0, i] as [NSNumber]] = NSNumber(value: left.acc.x + (right.acc.x - left.acc.x) * weight)
                    inputArray[[0, 1, i] as [NSNumber]] = NSNumber(value: left.acc.y + (right.acc.y - left.acc.y) * weight)
                    inputArray[[0, 2, i] as [NSNumber]] = NSNumber(value: left.acc.z + (right.acc.z - left.acc.z) * weight)
                    inputArray[[0, 3, i] as [NSNumber]] = NSNumber(value: left.gyro.x + (right.gyro.x - left.gyro.x) * weight)
                    inputArray[[0, 4, i] as [NSNumber]] = NSNumber(value: left.gyro.y + (right.gyro.y - left.gyro.y) * weight)
                    inputArray[[0, 5, i] as [NSNumber]] = NSNumber(value: left.gyro.z + (right.gyro.z - left.gyro.z) * weight)
                } else {
                    let last = validData.last!
                    inputArray[[0, 0, i] as [NSNumber]] = NSNumber(value: last.acc.x)
                    inputArray[[0, 1, i] as [NSNumber]] = NSNumber(value: last.acc.y)
                    inputArray[[0, 2, i] as [NSNumber]] = NSNumber(value: last.acc.z)
                    inputArray[[0, 3, i] as [NSNumber]] = NSNumber(value: last.gyro.x)
                    inputArray[[0, 4, i] as [NSNumber]] = NSNumber(value: last.gyro.y)
                    inputArray[[0, 5, i] as [NSNumber]] = NSNumber(value: last.gyro.z)
                }
            }
            
            do {
                let featureProvider = try MLDictionaryFeatureProvider(dictionary: [self.inputFeatureName: inputArray])
                let prediction = try model.prediction(from: featureProvider)
                guard let outputArray = prediction.featureValue(for: self.outputFeatureName)?.multiArrayValue else {
                    completion(nil, "Output parse failed"); return
                }
                
                // 绝对安全的扁平化提取（无视它是 [1, 2] 还是 [2] 的 Shape）
                let vx = outputArray[0].doubleValue
                let vy = outputArray[1].doubleValue
                
                if vx.isNaN || vy.isNaN || abs(vx) > 50 || abs(vy) > 50 {
                    completion(nil, "NaN or Out of Bounds"); return
                }
                completion(simd_double2(vx, vy), "Success: (\(String(format:"%.2f", vx)), \(String(format:"%.2f", vy)))")
            } catch {
                AppLogger.shared.log("ML Error: \(error.localizedDescription)")
                completion(nil, "Predict Error")
            }
        }
    }
}
