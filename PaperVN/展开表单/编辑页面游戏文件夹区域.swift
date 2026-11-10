import SwiftUI
import UniformTypeIdentifiers

/// 资料库编辑页里的游戏文件夹：添加、更改或移除。更改立即生效，不需要保存（文件夹只保存在这台设备上）。
struct 编辑页面游戏文件夹区域: View {
    let vnID: String

    @ObservedObject private var 中心 = 视觉小说文件夹中心.shared
    @State private var 显示选择 = false
    @State private var 正在识别 = false
    @State private var 错误: String?

    var body: some View {
        let record = 中心.记录(作品: vnID)
        Section {
            if let record {
                LabeledContent {
                    if 正在识别 {
                        ProgressView()
                    } else {
                        Text(verbatim: record.识别?.引擎.名称 ?? String(localized: "未知"))
                    }
                } label: {
                    Label {
                        Text(verbatim: record.名称)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "folder")
                    }
                }

                Button("更改文件夹") {
                    显示选择 = true
                }
                .disabled(正在识别)

                Button("移除文件夹", role: .destructive) {
                    中心.移除(作品: vnID)
                }
                .disabled(正在识别)
            } else {
                Button {
                    显示选择 = true
                } label: {
                    if 正在识别 {
                        ProgressView()
                    } else {
                        Text("添加文件夹")
                    }
                }
                .disabled(正在识别)
            }
        } header: {
            Text("模拟器")
        } footer: {
            Text(说明(record))
        }
        .fileImporter(isPresented: $显示选择, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            正在识别 = true
            Task {
                do {
                    try await 中心.设置(url, 作品: vnID)
                } catch {
                    错误 = error.localizedDescription
                }
                正在识别 = false
            }
        }
        .alert(
            "无法添加文件夹",
            isPresented: Binding(get: { 错误 != nil }, set: { if !$0 { 错误 = nil } })
        ) {
            Button("好") { 错误 = nil }
        } message: {
            Text(verbatim: 错误 ?? "")
        }
    }

    private func 说明(_ record: 视觉小说文件夹记录?) -> String {
        guard let record else {
            return String(localized: "添加此视觉小说的文件夹后，可以在PaperVN中运行。文件夹只保存在此设备上。")
        }
        guard let engine = record.识别?.引擎 else {
            return String(localized: "无法识别此文件夹中的视觉小说。")
        }
        if engine.可运行 {
            return String(localized: "文件夹只保存在此设备上。")
        }
        return String(format: String(localized: "PaperVN暂不支持运行使用%@的视觉小说。"), engine.名称)
    }
}
