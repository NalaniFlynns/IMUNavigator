import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    @State private var showCalibration = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(engine.statusText) \(engine.isZUPTActive ? "[ZUPT]" : "")", systemImage: engine.isRecording ? "record.circle" : "pause.circle")
                        .foregroundColor(engine.isRecording ? .green : .gray)
                        .font(.headline)
                    Text("Mem: \(engine.memorySizeText)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    if !engine.isRecording {
                        if AppSettings.shared.coreNavMode == .pureIMU && !AppSettings.shared.hasDoneRuntimeCalibration {
                            showCalibration = true
                        } else {
                            engine.startRecording()
                        }
                    } else { engine.stopRecording() }
                }) {
                    Text(engine.isRecording ? "Stop INS" : "Start INS").bold().padding(.horizontal, 20).padding(.vertical, 8).background(engine.isRecording ? Color.red.opacity(0.8) : Color.blue.opacity(0.8)).foregroundColor(.white).cornerRadius(8)
                }
            }.padding().background(Color(UIColor.secondarySystemBackground))
            .sheet(isPresented: $showCalibration) { CalibrationView(onCalibrationDone: { engine.startRecording() }).environmentObject(engine) }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                Label("\(engine.motionStateStr)", systemImage: (engine.motionStateStr == "Walking" || engine.motionStateStr == "Running") ? "figure.walk" : "figure.stand")
                    .foregroundColor(engine.motionStateStr == "Walking" ? .green : .orange)
                    .font(.system(size: 11, weight: .bold))
                
                Text("Engine: \(engine.activeEngine)").foregroundColor(.cyan).bold()
                Text("Sensors: \(engine.sensorStatus)")
                
                Text("SLAM Conf: \(engine.slamConfidence)")
                Text("Total Dist: \(String(format: "%.1f", engine.totalDistance))m")
                Text("Spd: \(String(format: "%.2f", engine.currentSpeed)) m/s")
                
                Text("Disp: \(String(format: "%.2f", engine.currentPoint?.stepDisplacement ?? 0))m")
                Text("Hdg Chg: \(String(format: "%.2f", engine.currentPoint?.headingChange ?? 0))°")
                Text("Bearing: \(String(format: "%.1f", engine.currentPoint?.bearingFromStart ?? 0))°")
                
                Text(String(format: "XYZ: (%.1f, %.1f, %.1f)m", engine.currentPoint?.x ?? 0, engine.currentPoint?.y ?? 0, engine.currentPoint?.z ?? 0))
                Text("Err: \(String(format: "%.3f", engine.cumulativeError))m")
                if let lat = engine.currentPoint?.latitude, let lon = engine.currentPoint?.longitude { Text(String(format: "LL: %.4f, %.4f", lat, lon)) } else { Text("LL: N/A") }
            }.font(.system(size: 11, design: .monospaced)).foregroundColor(.gray).padding()
            
            TrajectoryCanvas(points: engine.renderPoints, bounds: engine.renderBounds).frame(maxHeight: .infinity).background(Color.black.opacity(0.05)).cornerRadius(12).padding(.horizontal)
            
            VStack(alignment: .leading) {
                let firstTime = engine.chartPoints.first?.timestamp ?? 0
                if AppSettings.shared.showAltitudeChart {
                    Label("Altitude (m)", systemImage: "arrow.up.and.down.text.horizontal").font(.caption).foregroundColor(.gray)
                    Chart {
                        if engine.chartPoints.isEmpty { LineMark(x: .value("Time", 0), y: .value("Alt", 0)).foregroundStyle(.clear) }
                        ForEach(engine.chartPoints) { point in LineMark(x: .value("Time", point.timestamp - firstTime), y: .value("Alt", point.z)).foregroundStyle(.blue) }
                    }.chartXAxis(.hidden).frame(height: 35)
                }
                if AppSettings.shared.showErrorChart {
                    Label(AppSettings.shared.errorChartMode == .cumulative ? "Cumulative Drift Err (m)" : "1s Sliding Window Err (m)", systemImage: "chart.line.uptrend.xyaxis").font(.caption).foregroundColor(.gray)
                    Chart {
                        if engine.chartPoints.isEmpty { AreaMark(x: .value("Time", 0), y: .value("Err", 0)).foregroundStyle(.clear) }
                        ForEach(engine.chartPoints) { point in
                            let yVal = AppSettings.shared.errorChartMode == .cumulative ? point.cumulativeError : (point.instantaneousError ?? 0.0)
                            AreaMark(x: .value("Time", point.timestamp - firstTime), y: .value("Err", yVal)).foregroundStyle(.red.opacity(0.3))
                        }
                    }.chartXAxis(.hidden).frame(height: 35)
                }
                if AppSettings.shared.showResidualChart {
                    Label("NR-AR Pos Residual (m)", systemImage: "chart.xyaxis.line").font(.caption).foregroundColor(.gray)
                    Chart {
                        if engine.chartPoints.isEmpty { AreaMark(x: .value("Time", 0), y: .value("Res", 0)).foregroundStyle(.clear) }
                        ForEach(engine.chartPoints) { point in AreaMark(x: .value("Time", point.timestamp - firstTime), y: .value("Res", point.residual)).foregroundStyle(.orange.opacity(0.4)) }
                    }.chartXAxis(.hidden).frame(height: 30)
                    
                    Label("IMU-AR Accel Dev (m/s²)", systemImage: "bolt.horizontal.fill").font(.caption).foregroundColor(.gray)
                    Chart {
                        if engine.chartPoints.isEmpty { LineMark(x: .value("Time", 0), y: .value("AccRes", 0)).foregroundStyle(.clear) }
                        ForEach(engine.chartPoints) { point in LineMark(x: .value("Time", point.timestamp - firstTime), y: .value("AccRes", point.accResidual ?? 0)).foregroundStyle(.purple) }
                    }.chartXAxis(.hidden).frame(height: 30)
                }
            }.padding()
        }
    }
}
