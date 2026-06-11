import Foundation
import simd

enum TrackingSource: String, Codable {
    case arkitVIO = "VIO"
    case pedometerPDR = "PDR"
    case neuralNR = "NR"
    case imuFallback = "Pure_IMU"
}

struct SessionMetadata: Codable {
    let startTime: Date
    let recordingMode: String
    let timeInterval: Double
    let spaceInterval: Double
    let initialLatitude: Double?
    let initialLongitude: Double?
    let initialBarometerAlt: Double?
}

struct TrackingSession: Codable, Identifiable {
    let id: UUID
    let metadata: SessionMetadata
    var endTime: Date?
    var points: [TrackingPoint]
    var totalDistance: Double
}

struct TrackingPoint: Codable, Identifiable {
    let id: Int
    let timestamp: TimeInterval
    let source: TrackingSource
    
    let x: Double; let y: Double; let z: Double
    let speed: Double; let heading: Double
    let stepDisplacement: Double; let headingChange: Double
    let distanceFromStart: Double; let bearingFromStart: Double
    
    let cumulativeError: Double
    let instantaneousError: Double?
    let residual: Double
    let accResidual: Double?
    let isZUPTActive: Bool
    let slamConfidence: String
    
    var resX: Double?
    var resY: Double?
    
    let latitude: Double?
    let longitude: Double?
    let gnssAccuracy: Double?
    let gnssAltitude: Double?
    let barometerAltitude: Double?
    let acceleration: SIMD3<Double>?
    let rotationRate: SIMD3<Double>?
    let bleDevices: [BLEDevice]?
}

struct BLEDevice: Codable { let identifier: String; let rssi: Int }
