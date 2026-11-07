import SwiftUI

/// 会话列表页（占位）。
struct SessionsView: View {
    // TODO: 后续任务注入 SessionStore，用真实会话数据替换占位列表。
    // TODO: 后续任务在选中会话后跳转到终端视图。
    var body: some View {
        NavigationStack {
            List {
                // 占位：当前没有任何会话数据源。
            }
            .overlay {
                ContentUnavailableView(
                    "暂无会话",
                    systemImage: "terminal",
                    description: Text("连接网关后可在此开始会话。")
                )
            }
            .navigationTitle("会话")
        }
    }
}
