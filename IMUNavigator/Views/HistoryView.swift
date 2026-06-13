import SwiftUI
import SQLite3
import Charts

struct HistoryView: View {
    @State private var files: [URL] = []
    var body: some View {
        NavigationView {
            List {
                ForEach(files, id: \.self) { url in
                    NavigationLink(destination: SessionDetailView(fileURL: url, onDeleted: { loadFiles() })) {
                        HStack {
                            Image(systemName: url.pathExtension == "json" ? "doc.text.fill" : "cylinder.split.1x2.fill").foregroundColor(.blue)
                            VStack(alignment: .leading) { Text(url.deletingPathExtension().lastPathComponent).font(.headline); Text(fileSize(url: url)).font(.caption).foregroundColor(.gray) }
                        }
                    }
                }.onDelete(perform: deleteFiles)
            }.navigationTitle("Storage").onAppear(perform: loadFiles)
        }
    }
    func loadFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let urls = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey]) { self.files = urls.filter { $0.pathExtension == "json" || $0.pathExtension == "sqlite" }.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) }
    }
    func deleteFiles(at offsets: IndexSet) { for index in offsets { try? FileManager.default.removeItem(at: files[index]) }; loadFiles() }
    func fileSize(url: URL) -> String { guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int64 else { return "Unknown" }; return String(format: "%.2f MB", Double(size) / 1024.0 / 1024.0) }
}

struct SessionDetailView: View {
    @State var currentURL: URL; let onDeleted: () -> Void
    @State private var session: TrackingSession?
    @State private var renderPoints: [TrackingPoint] = []; @State private var chartPoints: [TrackingPoint] = []
    @State private var renderBounds = RenderBounds()
    @State private var selectedPoint: TrackingPoint?; @State private var isLoading = true
    @State private var showRenameAlert = false; @State private var newName = ""
    @Environment(\.presentationMode) var presentationMode
    
    init(fileURL: URL, onDeleted: @escaping () -> Void) { self._currentURL = State(initialValue: fileURL); self.onDeleted = onDeleted }
    
    var body: some View {
        VStack {
            if isLoading { ProgressView("Loading Large Session...") }
            else if let data = session {
                HStack { Text("Total Dist: \(String(format: "%.1f", data.totalDistance))m").bold(); Spacer(); Text("\(data.points.count) raw pts").foregroundColor(.gray) }.padding(.horizontal)
                TrajectoryCanvas(points: renderPoints, bounds: renderBounds, onPointSelected: { pt in selectedPoint = pt }).frame(minHeight: 200, maxHeight: .infinity).background(Color.black.opacity(0.05)).cornerRadius(12).padding(.horizontal)
                
                VStack(alignment: .leading) {
                    let firstTime = chartPoints.first?.timestamp ?? 0
                    if AppSettings.shared.showAltitudeChart {
                        Chart(chartPoints) { point in LineMark(x: .value("T", point.timestamp - firstTime), y: .value("A", point.z)).foregroundStyle(.blue) }.chartXAxis(.hidden).frame(height: 40)
                    }
                    if AppSettings.shared.showErrorChart {
                        Chart(chartPoints) { point in
                            let yVal = AppSettings.shared.errorChartMode == .cumulative ? point.cumulativeError : (point.instantaneousError ?? 0)
                            AreaMark(x: .value("T", point.timestamp - firstTime), y: .value("E", yVal)).foregroundStyle(.red.opacity(0.3))
                        }.chartXAxis(.hidden).frame(height: 40)
                    }
                }.padding(.horizontal)
                
                if let pt = selectedPoint {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Point ID: \(pt.id) [\(pt.source.rawValue)]").font(.headline)
                            let t = Date(timeIntervalSince1970: pt.timestamp).formatted(date: .omitted, time: .standard)
                            Text("Time: \(t)  |  ZUPT: \(pt.isZUPTActive ? "YES" : "NO")")
                            Text(String(format: "XYZ: (%.2f, %.2f, %.2f)m", pt.x, pt.y, pt.z))
                            Text(String(format: "Spd: %.2fm/s | Res: %.3fm", pt.speed, pt.residual))
                            Divider()
                            if let lat = pt.latitude, let lon = pt.longitude { Text(String(format: "GNSS LatLon: %.5f, %.5f", lat, lon)) } else { Text("GNSS LatLon: N/A") }
                            if let gAcc = pt.gnssAccuracy, let gAlt = pt.gnssAltitude { Text(String(format: "GNSS: Acc %.1fm | Alt %.1fm", gAcc, gAlt)) } else { Text("GNSS Acc/Alt: N/A") }
                            if let bAlt = pt.barometerAltitude { Text(String(format: "Baro Alt: %.2fm", bAlt)) } else { Text("Baro: N/A") }
                            if let acc = pt.acceleration { Text(String(format: "Accel XYZ: (%.2f, %.2f, %.2f)", acc.x, acc.y, acc.z)) } else { Text("Accel: N/A") }
                        }.font(.system(.footnote, design: .monospaced)).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                    }.frame(height: 140)
                } else { Spacer(); Text("Tap any point to view details").font(.caption).foregroundColor(.gray).padding(); Spacer() }
            } else { Text("Failed to load").foregroundColor(.red) }
        }
        .navigationTitle(currentURL.deletingPathExtension().lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { newName = currentURL.deletingPathExtension().lastPathComponent; showRenameAlert = true }) { Label("Rename", systemImage: "pencil") }
                    ShareLink(item: currentURL) { Label("Export", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive, action: deleteFile) { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }.onAppear { loadSessionDataAsync() }
        .alert("Rename File", isPresented: $showRenameAlert) { TextField("New Name", text: $newName); Button("Cancel", role: .cancel) { }; Button("Save") { let newURL = currentURL.deletingLastPathComponent().appendingPathComponent("\(newName).\(currentURL.pathExtension)"); if (try? FileManager.default.moveItem(at: currentURL, to: newURL)) != nil { currentURL = newURL; onDeleted() } } }
    }
    
    func loadSessionDataAsync() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedSession: TrackingSession? = nil
            if self.currentURL.pathExtension == "json" {
                if let raw = try? Data(contentsOf: self.currentURL), let decoded = try? JSONDecoder().decode(TrackingSession.self, from: raw) { loadedSession = decoded }
            } else if self.currentURL.pathExtension == "sqlite" {
                var db: OpaquePointer?; if sqlite3_open(self.currentURL.path, &db) == SQLITE_OK {
                    var stmt: OpaquePointer?; if sqlite3_prepare_v2(db, "SELECT metadata, points, distance FROM session LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            let metaString = String(cString: sqlite3_column_text(stmt, 0))
                            let meta = (try? JSONDecoder().decode(SessionMetadata.self, from: Data(metaString.utf8))) ?? SessionMetadata(startTime: Date(), recordingMode: "Unknown", timeInterval: 0, spaceInterval: 0, initialLatitude: nil, initialLongitude: nil, initialBarometerAlt: nil)
                            let ptsLen = sqlite3_column_bytes(stmt, 1); let ptsPtr = sqlite3_column_blob(stmt, 1)
                            let ptsData = Data(bytes: ptsPtr!, count: Int(ptsLen))
                            let pts = (try? JSONDecoder().decode([TrackingPoint].self, from: ptsData)) ?? []
                            let dist = sqlite3_column_double(stmt, 2)
                            loadedSession = TrackingSession(id: UUID(), metadata: meta, endTime: nil, points: pts, totalDistance: dist)
                        }
                    }; sqlite3_finalize(stmt); sqlite3_close(db)
                }
            }
            
            guard let session = loadedSession else { DispatchQueue.main.async { self.isLoading = false }; return }
            
            var rPts: [TrackingPoint] = []; var last: TrackingPoint? = nil
            for p in session.points {
                if let l = last {
                    let d = hypot(p.x - l.x, p.y - l.y); let a = abs(p.heading - l.heading)
                    if d > 0.2 || a > 5.0 { rPts.append(p); last = p }
                } else { rPts.append(p); last = p }
            }
            
            let xs = rPts.map { $0.x }; let ys = rPts.map { $0.y }; let zs = rPts.map { $0.z }
            let minX = xs.min() ?? 0; let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0; let maxY = ys.max() ?? 0
            let minZ = zs.min() ?? 0; let maxZ = zs.max() ?? 0
            let bounds = RenderBounds(center: CGPoint(x: (minX + maxX)/2, y: (minY + maxY)/2), maxRange: CGFloat(max(maxX - minX, maxY - minY, 1.0)), minZ: minZ, maxZ: maxZ)
            
            let step = max(1, rPts.count / 200)
            let cPoints = stride(from: 0, to: rPts.count, by: step).map { rPts[$0] }
            
            DispatchQueue.main.async {
                self.session = session; self.renderPoints = rPts; self.renderBounds = bounds; self.chartPoints = cPoints; self.isLoading = false
            }
        }
    }
    func deleteFile() { try? FileManager.default.removeItem(at: currentURL); presentationMode.wrappedValue.dismiss(); onDeleted() }
}
