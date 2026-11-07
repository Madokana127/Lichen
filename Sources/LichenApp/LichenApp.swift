import SwiftUI
import LichenCore

// TODO: 最终工程形态待后续任务确定——是否需要补充 .xcodeproj 或 Swift Playgrounds App 包装。
@main
public struct LichenApp: App {
    // TODO: 后续任务在此接入真实网关状态与应用生命周期（前后台切换、连接恢复）。
    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
