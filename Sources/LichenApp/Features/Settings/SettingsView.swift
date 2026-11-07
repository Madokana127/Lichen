import SwiftUI

/// 设置页（占位）。本任务不写入任何配置存储。
struct SettingsView: View {
    // TODO: 后续任务在此加入网关地址与鉴权配置入口。
    // TODO: 后续任务决定配置持久化方式（本任务明确不做）。
    var body: some View {
        NavigationStack {
            Form {
                Section("网关") {
                    // TODO: 后续任务跳转到 GatewayConfiguration 的编辑界面。
                    Text("尚未配置网关")
                        .foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("应用", value: "Lichen")
                    LabeledContent("形态", value: "框架骨架")
                }
            }
            .navigationTitle("设置")
        }
    }
}
