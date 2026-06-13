import SwiftUI

struct SpatialCalibrationLabView: View {
    @EnvironmentObject var engine: SensorFusionEngine
    var body: some View {
        // 隔离 Engine 刷新，保障滑块与手势
        SpatialLabContent(engine: engine).equatable()
    }
}

struct SpatialLabContent: View, Equatable {
    var engine: SensorFusionEngine
    
    static func == (lhs: SpatialLabContent, rhs: SpatialLabContent) -> Bool {
        return true // 拦截全局 10Hz 刷新
    }
    
    @StateObject private var settings = AppSettings.shared
    @State private var localYawOffset: Double = AppSettings.shared.imuYawOffset
    @State private var manualPan: CGSize = .zero
    @State private var manualZoom: CGFloat = 1.0

    var body: some View {
        VStack {
            Text("Spatial Alignment Lab").font(.headline).padding()
            Text("Green = VIO (ARKit) | Orange = NR/PDR (Blind)").font(.caption).foregroundColor(.gray)
            
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.1).cornerRadius(12)
                    // 仅 Canvas 内部重绘
                    SpatialCanvasView(engine: engine, settings: settings, manualPan: manualPan, manualZoom: manualZoom, localYawOffset: localYawOffset)
                }
                .gesture( DragGesture().onChanged { val in manualPan = val.translation } .simultaneously(with: MagnificationGesture().onChanged { val in manualZoom = val }) )
                .padding()
            }.frame(height: 300)
            
            VStack(spacing: 15) {
                Toggle("Auto Align (Velocity Vector)", isOn: $settings.enableAutoAlignment)
                
                if settings.enableAutoAlignment {
                    HStack { Text("Auto Yaw: "); Spacer(); AutoAlignText(engine: engine) }
                } else {
                    HStack { 
                        Text("Manual Yaw"); 
                        // 滑块实时应用
                        Slider(value: $localYawOffset, in: -180...180)
                            .onChange(of: localYawOffset) { val in settings.imuYawOffset = val }
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

struct SpatialCanvasView: View {
    @ObservedObject var engine: SensorFusionEngine
    @ObservedObject var settings: AppSettings
    var manualPan: CGSize
    var manualZoom: CGFloat
    var localYawOffset: Double
    
    var body: some View {
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
            
            context.translateBy(x: size.width/2 + manualPan.width, y: size.height/2 + manualPan.height)
            context.scaleBy(x: manualZoom, y: manualZoom)
            context.scaleBy(x: autoScale, y: autoScale)
            context.translateBy(x: -centerX, y: -centerY)
            
            var arPath = Path()
            if !arPoints.isEmpty {
                arPath.move(to: arPoints[0])
                for p in arPoints.dropFirst() { arPath.addLine(to: p) }
                context.stroke(arPath, with: .color(.green), lineWidth: 3 / autoScale / manualZoom)
            }
            
            var imuPath = Path()
            if !blindPoints.isEmpty {
                imuPath.move(to: blindPoints[0])
                for p in blindPoints.dropFirst() { imuPath.addLine(to: p) }
                context.stroke(imuPath, with: .color(.orange), lineWidth: 2 / autoScale / manualZoom)
            }
        }
    }
}

struct AutoAlignText: View {
    @ObservedObject var engine: SensorFusionEngine
    var body: some View {
        Text(String(format: "%.1f°", engine.autoAlignValueDisplay)).bold().foregroundColor(.blue)
    }
}
