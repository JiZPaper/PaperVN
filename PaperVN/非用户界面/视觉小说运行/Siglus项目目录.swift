import Foundation

/// 找出交给 siglus_rs 的游戏目录（Gameexe.dat 和 Scene.pck 所在的文件夹）。
/// 汉化补丁常常不替换原文件，而是另放 Scene.chs、Gameexe.chs 并改用 save_chs 存档；
/// siglus_rs 只认原版文件名，这时在 PaperVN 的数据文件夹里建一个映射目录，把文件按原版名称链接过去。
nonisolated enum Siglus项目目录 {
    static func 准备(游戏根目录 root: URL, 数据文件夹: URL) throws -> URL {
        guard let project = 找游戏目录(root) else {
            throw 视觉小说运行错误.无法识别
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        let names = Dictionary(entries.map { ($0.lastPathComponent.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        if names["scene.pck"] != nil { return project }
        guard let scene = names["scene.chs"] else {
            // 例如脚本被打包进了加过保护的程序里
            throw 视觉小说运行错误.无法读取(String(localized: "此文件夹中没有Scene.pck，PaperVN无法读取此视觉小说的脚本。"))
        }

        let mapped = 数据文件夹.appending(path: "Siglus", directoryHint: .isDirectory)
        let manager = FileManager.default
        // 每次按游戏文件夹现在的内容重建链接（适配版自带的 key.toml 也一起链接过去）
        try? manager.removeItem(at: mapped)
        try manager.createDirectory(at: mapped, withIntermediateDirectories: true)

        // 汉化版的存档：1.01 起是 save_chs，旧版是 save_cn；都没有时在游戏文件夹里新建 save_chs
        let saves = names["save_chs"] ?? names["save_cn"] ?? project.appending(path: "save_chs", directoryHint: .isDirectory)
        if !manager.fileExists(atPath: saves.path) {
            try? manager.createDirectory(at: saves, withIntermediateDirectories: true)
        }
        let replaced: Set<String> = ["scene.pck", "gameexe.dat", "scene.chs", "gameexe.chs", "savedata", "save_chs", "save_cn"]
        for entry in entries where !replaced.contains(entry.lastPathComponent.lowercased()) {
            try manager.createSymbolicLink(at: mapped.appending(path: entry.lastPathComponent), withDestinationURL: entry)
        }
        try manager.createSymbolicLink(at: mapped.appending(path: "Scene.pck"), withDestinationURL: scene)
        if let gameexe = names["gameexe.chs"] ?? names["gameexe.dat"] {
            try manager.createSymbolicLink(at: mapped.appending(path: "Gameexe.dat"), withDestinationURL: gameexe)
        }
        if manager.fileExists(atPath: saves.path) {
            try manager.createSymbolicLink(at: mapped.appending(path: "savedata"), withDestinationURL: saves)
        }
        return mapped
    }

    /// 识别出的文件夹里可能只有启动器（例如 StartData/GameData/SiglusEngine.exe，游戏在 data 里），往下找一层。
    private static func 找游戏目录(_ root: URL) -> URL? {
        func 是游戏目录(_ url: URL) -> Bool {
            let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).map { $0.lowercased() })
            return names.contains("gameexe.dat") || names.contains("gameexe.chs") || names.contains("scene.pck") || names.contains("scene.chs")
        }
        if 是游戏目录(root) { return root }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter(\.是文件夹).sorted { $0.lastPathComponent < $1.lastPathComponent }.first(where: 是游戏目录)
    }
}
