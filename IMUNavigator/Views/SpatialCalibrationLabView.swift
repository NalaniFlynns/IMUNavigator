import SwiftUI

struct SpatialCalibrationLabView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    @StateObject private var settings = AppSettings.shared
    
    @State private var localYawOffset: Double = AppSettings.shared.imuYawOffset
    
    var body: some View {
        VStack {
            Text("Spatial Alignment Lab").font(.headline).padding()
            Text("Green = VIO (ARKit) | Orange = NR/PDR (Blind)").font(.caption).foregroundColor(.gray)
            
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.1).cornerRadius(12)
                    Canvas { context, size in
                        
                        var arPoints: [CGPoint] = []
                        if let start = engine.windowAR.first?.1 {
                            arPoints = engine.windowAR.map { CGPoint(x: $0.1.x - start.x, y: -($0.1.y - start.y)) }
                        }
                        
                        var blindPoints: [CGPoint] = []
                        if let start = engine.windowBlind.first?.1 {
                            let yawRad = localYawOffset * .pi / 180.0
                            let cosY = cos(yawRad); let sinY = sin(yawRad)
                            blindPoints = engine.windowBlind.map { p in
                                let dx = p.1.x - start.x; let dy = p.1.y - start.y
                                var mx = dx * cosY - dy * sinY; var my = dx * sinY + dy * cosY
                                if settings.imuMirrorX { mx = -mx }
                                if settings.imuMirrorY { my = -my }
                                return CGPoint(x: mx, y: -my)
                            }
                        }
                        
                        let allPts = arPoints + blindPoints
                        guard !allPts.isEmpty else { return }
                        
                        let minX = allPts.map{$0.x}.min() ?? -1
                        let maxX = allPts.map{$0.x}.max() ?? 1
                        let minY = allPts.map{$0.y}.min() ?? -1
                        let maxY = allPts.map{$0.y}.max() ?? 1
                        
                        let rangeX = max(maxX - minX, 1.0)
                        let rangeY = max(maxY - minY, 1.0)
                        
                        let scaleX = size.width / rangeX * 0.85
                        let scaleY = size.height / rangeY * 0.85
                        let autoScale = min(scaleX, scaleY)
                        
                        let centerX = (maxX + minX) / 2.0
                        let centerY = (maxY + minY) / 2.0
                        
                        context.translateBy(x: size.width/2, y: size.height/2)
                        context.scaleBy(x: autoScale, y: autoScale)
                        context.translateBy(x: -centerX, y: -centerY)
                        
                        var arPath = Path()
                        if !arPoints.isEmpty {
                            arPath.move(to: arPoints[0])
                            for p in arPoints.dropFirst() { arPath.addLine(to: p) }
                            context.stroke(arPath, with: .color(.green), lineWidth: 3 / autoScale)
                        }
                        
                        var imuPath = Path()
                        if !blindPoints.isEmpty {
                            imuPath.move(to: blindPoints[0])
                            for p in blindPoints.dropFirst() { imuPath.addLine(to: p) }
                            context.stroke(imuPath, with: .color(.orange), lineWidth: 2 / autoScale)
                        }
                    }
                }
                .padding()
            }.frame(height: 300)
            
            VStack(spacing: 15) {

                Toggle("Auto Align (Velocity Vector)", isOn: $settings.enableAutoAlignment)
                
                if settings.enableAutoAlignment {
                    HStack { Text("Auto Yaw: "); Spacer(); Text(String(format: "%.1f°", engine.autoAlignValueDisplay)).bold().foregroundColor(.blue) }
                } else {
                    HStack {
                        Text("Manual Yaw");
                        Slider(value: Binding(
                            get: { localYawOffset },
                            set: { val in
                                localYawOffset = val
                                settings.imuYawOffset = val
                            }
                        ), in: -180...180)
                        Text(String(format: "%.1f°", localYawOffset)).frame(width: 50)
                    }
                }
                
                HStack { Toggle("Mirror X", isOn: $settings.imuMirrorX); Toggle("Mirror Y", isOn: $settings.imuMirrorY) }
            }.padding()
            Spacer()
        }
        .onAppear {
            localYawOffset = settings.imuYawOffset
        }
    }
}
