import Foundation

/// 视觉小说使用的引擎。识别依据是各引擎发行时固定会带的文件（脚本、封包、可执行文件），不读取游戏内容本身。
///
/// iOS 不能运行 Windows 程序，也不允许即时编译，所以每个引擎都要有自己的运行方式（见 `运行方式`）：
/// - 网页引擎（TyranoScript、RPG Maker MV/MZ、Ren'Py 网页版、其他 HTML5 游戏）：交给 WebKit，
///   资源由 `网页游戏资源` 从文件夹、package.nw、app.asar 或附加了 ZIP 的 exe 中读取。
/// - Ren'Py 电脑版：Ren'Py 官方的 WebAssembly 运行库 + 游戏的 game 文件夹（`RenPy原生读取器`）。
/// - NScripter（含 ONScripter）：由 `NScripter解释器` 直接解释脚本，用 SwiftUI 显示。
/// - YU-RIS：由 `YURIS虚拟机` 解释脚本，软件合成图层。
/// - SiglusEngine、RealLive、AVG32、UK2：siglus_rs。KiriKiri：krkr2。
/// 其他引擎只识别出名称，告诉用户暂时无法运行。
nonisolated enum 视觉小说引擎: String, Codable, Hashable, Sendable, CaseIterable {
    case nscripter
    case tyranoScript
    case rpgMakerMV
    case rpgMakerMZ
    case renPyWeb
    case html5
    case kirikiri
    case renPy
    case siglus
    case realLive
    case avg32
    case uk2
    case bgi
    case catSystem2
    case yuris
    case artemis
    case qlie
    case lightVN
    case unity
    case majiro
    case advHD
    case rpgMakerXP
    case rpgMakerVX
    case rpgMakerVXAce
    case rpgMaker2000

    /// 引擎的名称是专有名词，所有语言都不翻译。
    var 名称: String {
        switch self {
        case .nscripter: "NScripter"
        case .tyranoScript: "TyranoScript"
        case .rpgMakerMV: "RPG Maker MV"
        case .rpgMakerMZ: "RPG Maker MZ"
        case .renPyWeb: "Ren'Py Web"
        case .html5: "HTML5"
        case .kirikiri: "KiriKiri"
        case .renPy: "Ren'Py"
        case .siglus: "SiglusEngine"
        case .realLive: "RealLive"
        case .avg32: "AVG32"
        case .uk2: "UK2"
        case .bgi: "BGI"
        case .catSystem2: "CatSystem2"
        case .yuris: "YU-RIS"
        case .artemis: "Artemis"
        case .qlie: "QLIE"
        case .lightVN: "Light.vn"
        case .unity: "Unity"
        case .majiro: "Majiro"
        case .advHD: "AdvHD"
        case .rpgMakerXP: "RPG Maker XP"
        case .rpgMakerVX: "RPG Maker VX"
        case .rpgMakerVXAce: "RPG Maker VX Ace"
        case .rpgMaker2000: "RPG Maker 2000/2003"
        }
    }

    var 运行方式: 视觉小说运行方式? {
        switch self {
        case .nscripter: .nscripter
        case .siglus: .siglus
        case .kirikiri: .kirikiri
        case .realLive, .avg32, .uk2: .帧缓冲
        case .yuris: .yuris
        case .renPy: .renPy
        case .tyranoScript, .rpgMakerMV, .rpgMakerMZ, .renPyWeb, .html5: .网页
        default: nil
        }
    }

    var 可运行: Bool { 运行方式 != nil }

    /// game_fb_open 的 engine 参数
    var 帧缓冲引擎名: String {
        switch self {
        case .avg32: "avg32"
        case .uk2: "uk2"
        default: "reallive"
        }
    }
}

nonisolated enum 视觉小说运行方式: Sendable {
    case 网页
    case nscripter
    /// siglus_rs
    case siglus
    /// krkr2
    case kirikiri
    /// siglus_rs 的 RealLive、AVG32、UK2：每帧一张图
    case 帧缓冲
    /// 自己写的 YU-RIS 解释器
    case yuris
    /// 电脑版的 Ren'Py 游戏：只用它的 game 文件夹，由官方的 WebAssembly 运行库运行
    case renPy
}

/// 网页游戏的资源放在哪里。
nonisolated enum 网页游戏包: Codable, Hashable, Sendable {
    /// 普通文件夹，`入口` 是相对游戏根目录的 index.html 路径。
    case 文件夹(根目录: String, 入口: String)
    /// NW.js 的 package.nw，或附加在 exe 末尾的 ZIP（`偏移` 是 ZIP 在文件中的起点）。
    case zip(文件: String, 偏移: UInt64, 入口: String)
    /// Electron 的 app.asar。
    case asar(文件: String, 入口: String)
}

nonisolated struct 视觉小说引擎识别结果: Codable, Hashable, Sendable {
    let 引擎: 视觉小说引擎
    /// 相对所选文件夹的游戏根目录（用户选了上一层文件夹时不为空）。
    let 根目录: String
    var 网页包: 网页游戏包?
}

nonisolated enum 视觉小说引擎识别 {
    /// 往下找几层。用户常会选中游戏外面一层（例如解压出来的文件夹），游戏本体也可能在 StartData 之类的子文件夹里。
    private static let 最大深度 = 3
    private static let 最多检查文件夹数 = 80

    static func 识别(_ folder: URL) -> 视觉小说引擎识别结果? {
        var queue: [(url: URL, relative: String, depth: Int)] = [(folder, "", 0)]
        var checked = 0
        // 先把所有层的候选找出来，再按优先级选：可以运行的优先，同等时浅的优先
        var candidates: [视觉小说引擎识别结果] = []
        while !queue.isEmpty, checked < 最多检查文件夹数 {
            let current = queue.removeFirst()
            checked += 1
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            if let result = 识别单层(current.url, entries: entries, relative: current.relative) {
                candidates.append(result)
                // 识别出引擎的文件夹不再往下找，下面多半是它自己的资源
                continue
            }
            guard current.depth < 最大深度 else { continue }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where entry.是文件夹 {
                let name = entry.lastPathComponent
                guard !跳过的文件夹.contains(name.lowercased()) else { continue }
                queue.append((entry, current.relative.isEmpty ? name : "\(current.relative)/\(name)", current.depth + 1))
            }
        }
        return candidates.first(where: \.引擎.可运行) ?? candidates.first
    }

    /// 备份、补丁、存档这类文件夹里常有另一份游戏文件，不在里面识别。
    private static let 跳过的文件夹: Set<String> = [
        "save", "savedata", "save_cn", "screenshots", "manual", "__macosx", "monobleedingedge",
    ]

    private static func 识别单层(_ url: URL, entries: [URL], relative: String) -> 视觉小说引擎识别结果? {
        let names = Dictionary(entries.map { ($0.lastPathComponent.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let extensions = Set(entries.map { $0.pathExtension.lowercased() })
        func has(_ name: String) -> Bool { names[name] != nil }
        func dir(_ name: String) -> Bool { names[name]?.是文件夹 == true }
        func result(_ engine: 视觉小说引擎, _ package: 网页游戏包? = nil) -> 视觉小说引擎识别结果 {
            .init(引擎: engine, 根目录: relative, 网页包: package)
        }

        // 网页引擎：直接放在文件夹里。只有 index.html、认不出是哪个网页引擎时，先看看是不是别的引擎附带的说明页
        var 通用网页: 视觉小说引擎识别结果?
        for prefix in ["", "www/"] {
            let base = prefix.isEmpty ? url : url.appending(path: "www", directoryHint: .isDirectory)
            let index = prefix + "index.html"
            guard FileManager.default.fileExists(atPath: base.appending(path: "index.html").path) else { continue }
            let package = 网页游戏包.文件夹(根目录: relative, 入口: index)
            let js = base.appending(path: "js", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: js.appending(path: "rmmz_core.js").path) { return result(.rpgMakerMZ, package) }
            if FileManager.default.fileExists(atPath: js.appending(path: "rpg_core.js").path) { return result(.rpgMakerMV, package) }
            if FileManager.default.fileExists(atPath: base.appending(path: "tyrano", directoryHint: .isDirectory).path) {
                return result(.tyranoScript, package)
            }
            if FileManager.default.fileExists(atPath: base.appending(path: "renpy.wasm").path)
                || FileManager.default.fileExists(atPath: base.appending(path: "game.zip").path) {
                return result(.renPyWeb, package)
            }
            if 通用网页 == nil { 通用网页 = result(.html5, package) }
        }

        // NScripter：脚本是 0.txt～99.txt、00.txt 或 nscript.dat，资源在 .nsa/.sar 中
        if has("0.txt") || has("00.txt") || has("nscript.dat") || has("nscr_sec.dat") || has("nscript.___")
            || names.keys.contains(where: { $0.hasPrefix("onscript.nt") }) {
            return result(.nscripter)
        }

        // NW.js：package.nw（ZIP），或 Electron 的 resources/app.asar
        if let file = names["package.nw"], !file.是文件夹,
           let found = 网页游戏资源.识别ZIP包(file, relative: 相对(relative, file.lastPathComponent)) {
            return result(found.引擎, found.包)
        }
        if let resources = names["resources"], resources.是文件夹 {
            let asar = resources.appending(path: "app.asar")
            if FileManager.default.fileExists(atPath: asar.path),
               let found = 网页游戏资源.识别ASAR包(asar, relative: 相对(relative, "resources/app.asar")) {
                return result(found.引擎, found.包)
            }
        }

        // KiriKiri：封包 .xp3，或者没打包的 startup.tjs
        if extensions.contains("xp3") || has("startup.tjs") { return result(.kirikiri) }
        if dir("renpy") || (dir("game") && 子文件夹包含(names["game"], 扩展名: ["rpa", "rpyc", "rpy"])) {
            return result(.renPy)
        }
        if has("scene.pck") || has("gameexe.dat") || names.keys.contains(where: { $0.hasPrefix("siglusengine") }) {
            return result(.siglus)
        }
        if has("seen.txt") || has("gameexe.ini") || has("reallive.exe") || has("uk2.cfg") || has("uk2.exe") {
            return result(帧缓冲引擎识别.引擎(url) ?? .realLive)
        }
        if extensions.contains("mcdat") || has("lighttests.exe") || 子文件夹包含(names["data"], 扩展名: ["mcdat"]) {
            return result(.lightVN)
        }
        if extensions.contains("ypf") || has("yscfg.dat") || dir("ysbin") { return result(.yuris) }
        if 子文件夹包含(names["pac"], 扩展名: ["ypf"]) { return result(.yuris) }
        if extensions.contains("pfs") { return result(.artemis) }
        if has("bgi.exe") || has("sysgrp.arc") || has("bgi.gdb") { return result(.bgi) }
        if has("cs2conf.dll") || names.keys.contains(where: { $0.hasPrefix("cs2") && $0.hasSuffix(".exe") }) {
            return result(.catSystem2)
        }
        if extensions.contains("int"), has("config") { return result(.catSystem2) }
        if 子文件夹包含(names["gamedata"], 扩展名: ["pack"]) { return result(.qlie) }
        if has("unityplayer.dll") || entries.contains(where: { $0.lastPathComponent.hasSuffix("_Data") && $0.是文件夹 }) {
            return result(.unity)
        }
        if has("advhd.exe") { return result(.advHD) }
        if names.keys.contains(where: { $0.hasPrefix("majiro") }) { return result(.majiro) }
        if has("game.rgss3a") || 子文件夹包含(names["data"], 扩展名: ["rvdata2"]) { return result(.rpgMakerVXAce) }
        if has("game.rgss2a") || 子文件夹包含(names["data"], 扩展名: ["rvdata"]) { return result(.rpgMakerVX) }
        if has("game.rgssad") || 子文件夹包含(names["data"], 扩展名: ["rxdata"]) { return result(.rpgMakerXP) }
        if has("rpg_rt.exe") || has("rpg_rt.ldb") { return result(.rpgMaker2000) }

        // TyranoBuilder 等导出的 Windows 版是把 package.nw 直接接在 nw.exe 后面
        for exe in entries where exe.pathExtension.lowercased() == "exe" && !exe.是文件夹 {
            // 普通 exe 末尾没有 ZIP，读到中央目录结束记录就会失败，不会整个读进来
            if let found = 网页游戏资源.识别ZIP包(exe, relative: 相对(relative, exe.lastPathComponent)) {
                return result(found.引擎, found.包)
            }
        }
        return 通用网页
    }

    private static func 相对(_ base: String, _ name: String) -> String {
        base.isEmpty ? name : "\(base)/\(name)"
    }

    private static func 子文件夹包含(_ folder: URL?, 扩展名 extensions: Set<String>) -> Bool {
        guard let folder, folder.是文件夹,
              let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return false }
        var count = 0
        for case let file as URL in enumerator {
            count += 1
            if extensions.contains(file.pathExtension.lowercased()) { return true }
            if count > 400 { break }
        }
        return false
    }
}

nonisolated extension URL {
    var 是文件夹: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
