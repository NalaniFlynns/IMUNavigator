import ActivityKit
import WidgetKit
import SwiftUI

@main
struct INSLiveActivityBundle: WidgetBundle { 
    var body: some Widget { INSLiveActivity() } 
}

struct INSLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: INSActivityAttributes.self) { context in
            VStack {
                HStack { 
                    Image(systemName: context.state.isZUPT ? "pause.circle.fill" : "location.north.line.fill")
                        .foregroundColor(context.state.isZUPT ? .orange : .green)
                    Text("INS Tracking").bold()
                    Spacer()
                    Text(context.state.activeEngine).font(.caption).foregroundColor(.secondary) 
                }
                HStack { 
                    Text("Dist: \(String(format: "%.1f", context.state.distance))m")
                    Spacer()
                    Text("Mot: \(context.state.motionState)") 
                }
                .font(.system(.body, design: .monospaced))
                .padding(.top, 4)
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("\(String(format: "%.1f", context.state.distance))m", systemImage: "ruler") }
                DynamicIslandExpandedRegion(.trailing) { Label("\(String(format: "%.1f", context.state.speed))m/s", systemImage: "speedometer") }
                DynamicIslandExpandedRegion(.bottom) { 
                    HStack { 
                        Image(systemName: "cpu")
                        Text(context.state.activeEngine + " | " + context.state.motionState) 
                    }
                    .font(.caption)
                    .foregroundColor(context.state.isZUPT ? .orange : .green) 
                }
            } compactLeading: { 
                Image(systemName: context.state.isZUPT ? "pause.circle.fill" : "location.north.line.fill")
                    .foregroundColor(context.state.isZUPT ? .orange : .green) 
            }
            compactTrailing: { Text("\(String(format: "%.0f", context.state.distance))m").font(.caption2).bold() }
            minimal: { Image(systemName: "location.north.line.fill").foregroundColor(context.state.isZUPT ? .orange : .green) }
        }
    }
}
