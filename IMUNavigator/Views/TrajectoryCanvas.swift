import SwiftUI
import simd

struct TrajectoryCanvas: View {
    var points: [TrackingPoint]
    var bounds: RenderBounds
    var onPointSelected: ((TrackingPoint) -> Void)? = nil
    
    @AppStorage("autoRotateCanvas") var autoRotateCanvas: Bool = true
    
    @State private var isAutoTracking: Bool = true
    @State private var zoomLevelIndex: Int = 1
    let zoomLevels: [CGFloat] = [0.5, 1.0, 1.5]
    
    @State private var frozenCenter: CGPoint = .zero
    @State private var frozenScale: CGFloat = 1.0
    @State private var frozenRotation: Angle = .zero
    
    @State private var screenPan: CGSize = .zero
    @State private var activePan: CGSize = .zero
    @State private var manualZoom: CGFloat = 1.0
    @State private var manualRotationAdd: Angle = .zero
    @State private var selectedPointID: Int? = nil
    
    func colorForAlt(_ z: Double, minZ: Double, maxZ: Double) -> Color {
        let range = max(maxZ - minZ, 0.1); let norm = (z - minZ) / range
        if norm < 0.5 { let f = norm * 2.0; return Color(red: 0, green: f, blue: 1.0 - f) }
        else { let f = (norm - 0.5) * 2.0; return Color(red: f, green: 1.0 - f, blue: 0) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let autoCenter = bounds.center
            let autoBaseScale = min(geometry.size.width, geometry.size.height) / bounds.maxRange * 0.8
            let autoScale = autoBaseScale * zoomLevels[zoomLevelIndex]
            let autoRotation = autoRotateCanvas ? Angle.degrees(-(points.last?.heading ?? 0)) : .zero
            
            let currentCenter = isAutoTracking ? autoCenter : frozenCenter
            let currentScale = (isAutoTracking ? autoScale : frozenScale) * manualZoom
            let currentRotation = (isAutoTracking ? autoRotation : frozenRotation) + manualRotationAdd
            
            let totalPanX = isAutoTracking ? 0 : screenPan.width + activePan.width
            let totalPanY = isAutoTracking ? 0 : screenPan.height + activePan.height
            
            let freeze = {
                if isAutoTracking {
                    frozenCenter = autoCenter; frozenScale = autoScale; frozenRotation = autoRotation
                    screenPan = .zero; activePan = .zero; manualZoom = 1.0; manualRotationAdd = .zero
                    isAutoTracking = false
                }
            }
            
            let panGesture = DragGesture().onChanged { val in freeze(); activePan = val.translation }.onEnded { val in screenPan.width += val.translation.width; screenPan.height += val.translation.height; activePan = .zero }
            let zoomGesture = MagnificationGesture().onChanged { val in freeze(); manualZoom = val }.onEnded { val in frozenScale *= val; manualZoom = 1.0 }
            let rotGesture = RotationGesture().onChanged { val in freeze(); manualRotationAdd = val }.onEnded { val in frozenRotation += val; manualRotationAdd = .zero }
            
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard !points.isEmpty else { return }
                    context.translateBy(x: size.width/2 + totalPanX, y: size.height/2 + totalPanY)
                    context.rotate(by: currentRotation)
                    context.scaleBy(x: currentScale, y: -currentScale)
                    context.translateBy(x: -currentCenter.x, y: -currentCenter.y)
                    
                    // LOD Pixel Threshold Overdraw Optimization
                    let pixelThreshold: CGFloat = 2.0
                    var lastDrawnIndex = 0
                    
                    for i in 1..<points.count {
                        let p1 = points[lastDrawnIndex]
                        let p2 = points[i]
                        
                        let physicalDist = hypot(p2.x - p1.x, p2.y - p1.y)
                        let pixelDist = CGFloat(physicalDist) * currentScale
                        
                        if pixelDist >= pixelThreshold || i == points.count - 1 || p2.id == selectedPointID {
                            var path = Path()
                            path.move(to: CGPoint(x: p1.x, y: p1.y))
                            path.addLine(to: CGPoint(x: p2.x, y: p2.y))
                            context.stroke(path, with: .color(colorForAlt(p2.z, minZ: bounds.minZ, maxZ: bounds.maxZ)), lineWidth: 2 / currentScale)
                            lastDrawnIndex = i
                        }
                    }
                    
                    if let first = points.first { context.fill(Path(ellipseIn: CGRect(x: first.x - 4/currentScale, y: first.y - 4/currentScale, width: 8/currentScale, height: 8/currentScale)), with: .color(.green)); context.draw(Text("Start").font(.system(size: 10/currentScale, weight: .bold)).foregroundColor(.green), at: CGPoint(x: first.x, y: first.y + 12/currentScale)) }
                    if let selID = selectedPointID, let selPoint = points.first(where: { $0.id == selID }) { context.fill(Path(ellipseIn: CGRect(x: selPoint.x - 6/currentScale, y: selPoint.y - 6/currentScale, width: 12/currentScale, height: 12/currentScale)), with: .color(.yellow)) }
                    if let last = points.last { context.fill(Path(ellipseIn: CGRect(x: last.x - 4/currentScale, y: last.y - 4/currentScale, width: 8/currentScale, height: 8/currentScale)), with: .color(.red)); var ptr = Path(); ptr.move(to: CGPoint(x: last.x, y: last.y + 12/currentScale)); ptr.addLine(to: CGPoint(x: last.x - 6/currentScale, y: last.y - 6/currentScale)); ptr.addLine(to: CGPoint(x: last.x + 6/currentScale, y: last.y - 6/currentScale)); context.fill(ptr, with: .color(.blue)) }
                }
                .onTapGesture { location in
                    guard onPointSelected != nil else { return }
                    let cx = Double(geometry.size.width/2 + totalPanX); let cy = Double(geometry.size.height/2 + totalPanY)
                    let dx = Double(location.x) - cx; let dy = Double(location.y) - cy; let angle = -currentRotation.radians
                    let rdx = dx * cos(angle) - dy * sin(angle); let rdy = dx * sin(angle) + dy * cos(angle)
                    let worldX = rdx / Double(currentScale) + Double(currentCenter.x); let worldY = rdy / Double(-currentScale) + Double(currentCenter.y)
                    if let closest = points.min(by: { hypot($0.x - worldX, $0.y - worldY) < hypot($1.x - worldX, $1.y - worldY) }) { selectedPointID = closest.id; onPointSelected?(closest) }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { if isAutoTracking { zoomLevelIndex = (zoomLevelIndex + 1) % zoomLevels.count } else { isAutoTracking = true; zoomLevelIndex = 1 } }) {
                        HStack { Image(systemName: isAutoTracking ? "lock.fill" : "lock.open.fill"); Text(isAutoTracking ? "Zoom: \(zoomLevels[zoomLevelIndex], specifier: "%.1f")x" : "Restore Auto") }.font(.caption).padding(8).background(.ultraThinMaterial).cornerRadius(8)
                    }.buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom, spacing: 4) { Rectangle().frame(width: 2, height: 40).foregroundColor(.secondary); Text("\(40 / currentScale, specifier: "%.1f")m").font(.caption2).foregroundColor(.secondary) }
                        if !points.isEmpty { HStack(spacing: 4) { LinearGradient(gradient: Gradient(colors: [.red, .green, .blue]), startPoint: .top, endPoint: .bottom).frame(width: 4, height: 60).cornerRadius(2); VStack(alignment: .leading) { Text("\(bounds.maxZ, specifier: "%.1f")").font(.system(size: 8)).foregroundColor(.secondary); Spacer(); Text("\(bounds.minZ, specifier: "%.1f")").font(.system(size: 8)).foregroundColor(.secondary) } }.frame(height: 60) }
                    }.padding(.leading, 8)
                }.padding(8)
                VStack { Spacer(); HStack { Spacer(); ZStack { Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36); VStack(spacing: 0) { Text("N").font(.system(size: 10, weight: .bold)).foregroundColor(.red); Image(systemName: "location.north.fill").foregroundColor(.red) }.rotationEffect(currentRotation) }.padding(8) } }
            }
            .gesture(panGesture.simultaneously(with: zoomGesture).simultaneously(with: rotGesture))
        }
    }
}
