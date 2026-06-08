import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    @Environment(\.dismiss) var dismiss
    var onCalibrationDone: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Static Bias Calibration").font(.title2).bold().padding(.top)
            Text("Place the device flat & completely stationary. It takes 5 seconds to sample 500 frames.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
            
            VStack(spacing: 15) {
                CalibrationBar(axis: "X (East)", value: engine.liveEarthAcc.x)
                CalibrationBar(axis: "Y (North)", value: engine.liveEarthAcc.y)
                CalibrationBar(axis: "Z (Up)", value: engine.liveEarthAcc.z)
            }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12).padding()
            
            if engine.isCalibrating {
                ProgressView(value: engine.calibrationProgress).progressViewStyle(LinearProgressViewStyle(tint: .blue)).padding()
                Text(String(format: "Calibrating... %.0f%%", engine.calibrationProgress * 100)).font(.caption).foregroundColor(.blue)
            } else {
                Button(action: {
                    engine.triggerManualCalibration {
                        dismiss()
                        onCalibrationDone?()
                    }
                }) { 
                    Text("Start 5s Calibration").bold().frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(12) 
                }.padding(.horizontal)
            }
            Spacer()
        }
    }
}

struct CalibrationBar: View {
    var axis: String; var value: Double
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(axis).font(.caption).foregroundColor(.gray); Spacer(); Text(String(format: "%.3f m/s²", value)).font(.system(.caption, design: .monospaced)) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.3))
                    let normalized = CGFloat(min(max((value + 2.0) / 4.0, 0.0), 1.0))
                    Rectangle().fill(abs(value) < 0.1 ? Color.green : Color.orange).frame(width: geo.size.width * normalized)
                }
            }.frame(height: 10).cornerRadius(5)
        }
    }
}
