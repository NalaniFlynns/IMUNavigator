import ActivityKit
import Foundation

public struct INSActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distance: Double
        public var speed: Double
        public var statusText: String
        public var activeEngine: String
        public var motionState: String
        public var isZUPT: Bool
    }
    public var sessionName: String
    public init(sessionName: String) { self.sessionName = sessionName }
}