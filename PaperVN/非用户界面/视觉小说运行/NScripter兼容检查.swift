import AVFoundation
import CoreText
import Foundation

/// 运行前就能看出来、和原版效果不一样的地方，启动时提示一次。
nonisolated enum 视觉小说兼容问题: Hashable, Sendable {
    /// 游戏自带的字体用不了，改用系统字体
    case 字体(String)
    /// 这些格式的声音解码不了
    case 声音格式([String])
    case 视频
    /// 脚本用到了解释器还没实现的命令
    case 部分功能

    /// 记录“不再显示”用，和界面语言无关
    var 标识: String {
        switch self {
        case .字体(let name): "font:\(name)"
        case .声音格式(let formats): "sound:\(formats.joined(separator: ","))"
        case .视频: "video"
        case .部分功能: "commands"
        }
    }

    var 说明: String {
        switch self {
        case .字体(let name): String(localized: "“\(name)”将使用系统字体显示。")
        case .声音格式(let formats): String(localized: "\(formats.formatted(.list(type: .and)))格式的声音不会播放。")
        case .视频: String(localized: "视频不会播放。")
        case .部分功能: String(localized: "此视觉小说用到了PaperVN尚不支持的部分功能。")
        }
    }
}

nonisolated enum NScripter兼容检查 {
    struct 结果: Sendable {
        /// 能用的游戏字体，nil 时用系统字体
        var 字体文件: URL?
        var 问题: [视觉小说兼容问题]
    }

    static func 检查(脚本 script: NScripter脚本, 资源 resources: NScripter资源) -> 结果 {
        var issues: [视觉小说兼容问题] = []
        let font = 检查字体(script, resources)
        if let name = font.不可用 { issues.append(.字体(name)) }
        let formats = 检查声音(resources)
        if !formats.isEmpty { issues.append(.声音格式(formats)) }
        let commands = 用到的未支持命令(script)
        // 影片自己解码。每种格式挑最小的文件试着打开，打不开才提示
        let unplayableVideo = 有打不开的影片(resources)
        if !commands.isDisjoint(with: 视频命令), unplayableVideo { issues.append(.视频) }
        if !commands.isEmpty, !commands.subtracting(视频命令).isEmpty { issues.append(.部分功能) }
        return 结果(字体文件: font.可用, 问题: issues)
    }

    private static func 有打不开的影片(_ resources: NScripter资源) -> Bool {
        FFmpeg影片后端.启用()
        var smallest: [String: (path: String, size: Int)] = [:]
        for path in resources.全部文件 {
            let ext = (path as NSString).pathExtension.lowercased()
            guard ["mpg", "mpeg", "avi", "wmv", "asf", "mp4", "m4v", "mov", "ogv", "flv"].contains(ext) else { continue }
            let size = resources.大小(path) ?? .max
            if size < smallest[ext]?.size ?? .max { smallest[ext] = (path, size) }
        }
        return smallest.values.contains { file in
            guard let data = resources.读取(file.path), !data.isEmpty else { return false }
            return 视觉小说影片.打开(数据: data, 顺序: .bgra, 声音: false) == nil
        }
    }

    // MARK: 字体

    /// 和 ONScripter 一样用文件夹里的 default.ttf，没有时用第一个字体文件。
    static func 游戏字体(_ resources: NScripter资源) -> URL? {
        let fonts = resources.文件夹文件.filter { !$0.contains("/") && ["ttf", "ttc", "otf"].contains(($0 as NSString).pathExtension) }
        let preferred = fonts.first { $0 == "default.ttf" } ?? fonts.sorted().first
        return preferred.flatMap { resources.文件夹地址($0) }
    }

    /// 汉化版常把日文汉字留在脚本里，字体缺几个字时 Windows 上也会换别的字体显示，不算问题；
    /// 大部分字都没有（字符表是旧编码、字体文件坏了）才改用系统字体。
    private static func 检查字体(_ script: NScripter脚本, _ resources: NScripter资源) -> (可用: URL?, 不可用: String?) {
        guard let url = 游戏字体(resources) else { return (nil, nil) }
        let name = url.deletingPathExtension().lastPathComponent
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            return (nil, name)
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        var characters = Set<UInt16>()
        for line in script.行 {
            for unit in line.utf16 where unit > 0x7f && !UTF16.isLeadSurrogate(unit) && !UTF16.isTrailSurrogate(unit) {
                characters.insert(unit)
            }
            if characters.count >= 3000 { break }
        }
        guard !characters.isEmpty else { return (url, nil) }
        var missing = 0
        for character in characters {
            var unit = character
            var glyph: CGGlyph = 0
            if !CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1) { missing += 1 }
        }
        return Double(missing) / Double(characters.count) > 0.2 ? (nil, name) : (url, nil)
    }

    // MARK: 声音

    private static let 声音扩展名 = ["wav", "mp3", "ogg", "mid", "midi", "m4a", "aac", "flac", "opus", "wma"]

    /// 每种格式挑最小的一个文件试着解码，解不了的格式返回给用户看的名称。
    private static func 检查声音(_ resources: NScripter资源) -> [String] {
        var smallest: [String: (path: String, size: Int)] = [:]
        for path in resources.全部文件 {
            let ext = (path as NSString).pathExtension
            guard 声音扩展名.contains(ext) else { continue }
            let size = resources.大小(path) ?? .max
            if size < smallest[ext]?.size ?? .max || smallest[ext] == nil { smallest[ext] = (path, size) }
        }
        var formats: [String] = []
        for (ext, file) in smallest.sorted(by: { $0.key < $1.key }) {
            guard let data = resources.读取(file.path), !data.isEmpty else { continue }
            if data.prefix(4) == Data("MThd".utf8) { continue } // MIDI 用自带的音色库播放
            let playable: Data = data.prefix(4) == Data("OggS".utf8) ? (NScripterOgg.解码成WAV(data) ?? data) : data
            if (try? AVAudioPlayer(data: playable)) == nil {
                let format = switch ext {
                case "mid", "midi": "MIDI"
                case "ogg": "Ogg"
                case "opus": "Opus"
                case "flac": "FLAC"
                default: ext.uppercased()
                }
                if !formats.contains(format) { formats.append(format) }
            }
        }
        return formats
    }

    // MARK: 命令

    private static let 视频命令: Set<String> = ["movie", "mpegplay", "avi"]

    /// 解释器认得但还没实现的命令，加上要看文件格式才知道能不能放的视频命令。
    static let 未支持命令: Set<String> = [
        "textgosub", "pretextgosub", "movie", "mpegplay", "avi", "exec_dll", "draw", "cselbtn",
        "btntime", "btntime2", "exbtn", "exbtn_d", "transbtn",
    ]

    /// 解释器实现了的命令（和 `NScripter解释器.执行命令` 的 case 一致，那边加了命令这里也要加）。
    static let 已支持命令: Set<String> = [
        "abssetcursor", "add", "addkinsoku", "allsp2hide", "allsp2resume", "allsphide", "allspresume", "amsp", "amsp2",
        "arc", "atoi", "autoclick", "automode", "automode_time", "bdown", "bg", "bgm", "bgmfadeout", "bgmonce",
        "bgmstop", "bgmvol", "br", "break", "btn", "btndef", "btndown", "btnwait", "btnwait2", "caption", "cell",
        "checkpage", "chvol", "cl", "click", "clickstr", "clickvoice", "cmp", "csel", "cselgoto", "csp", "csp2", "date",
        "dec", "defaultfont", "defaultspeed", "defbgmvol", "defmp3vol", "defsevol", "defsub", "defvoicevol", "delay",
        "deletemenu", "dim", "div", "drawbg", "drawclear", "drawfill", "drawsp", "drawtext", "dwave", "dwaveload",
        "dwaveloop", "dwaveplay", "dwaveplayloop", "dwavestop", "effect", "effectblank", "end", "erasetextbtn",
        "erasetextwindow", "fileexist", "filelog", "for", "game", "getbtntimer", "getcselnum", "getcursor",
        "getcursorpos", "getini", "getlog", "getmouseover", "getmousepos", "getparam", "getreg", "getret", "getsavestr",
        "getscreenshot", "getskipoff", "getspmode", "getspsize", "gettag", "gettext", "gettimer", "getversion",
        "getwindowsize", "globalon", "globalon_off", "gosub", "goto", "humanorder", "humanz", "if", "inc", "intlimit",
        "isdown", "isfull", "ispage", "isskip", "itoa", "itoa2", "jumpb", "jumpf", "kidokumode", "kidokuskip",
        "killmenu", "labellog", "layermessage", "ld", "len", "linepage", "linepage2", "load", "loadgame", "loadgosub",
        "locate", "logsp", "logsp2", "lookback", "lookbackbutton", "lookbackcolor", "lookbackflush", "loopbgm",
        "lr_trap", "lr_trap2", "lrclick", "lsp", "lsp2", "lsph", "lsph2", "maxkaisoupage", "menuselectcolor",
        "menuselectvoice", "menusetwindow", "mid", "minimizewindow", "mod", "mode_ext", "mode_saya", "mode_wave_demo",
        "monocro", "mouse_mode", "mousecursor", "mov", "mov10", "mov3", "mov4", "mov5", "mov6", "mov7", "mov8", "mov9",
        "movl", "mp3", "mp3fadeout", "mp3loop", "mp3save", "mp3stop", "mp3vol", "msp", "msp2", "mul", "nega", "next",
        "noloaderror", "notif", "ns2", "nsa", "nsadir", "nsadir2", "numalias", "play", "playonce", "playstop", "print",
        "quake", "quakex", "quakey", "reset", "resettimer", "return", "rgosub", "rlookback", "rmenu", "rnd", "rnd2",
        "roff", "save", "savedir", "savegame", "savegame2", "savename", "savenumber", "saveoff", "saveon", "select",
        "selectbtnwait", "selectcolor", "selectvoice", "selgosub", "selnum", "setcursor", "setkinsoku", "setlayer",
        "setlayer2", "setwindow", "setwindow2", "setwindow3", "sevol", "shadedistance", "skip", "skipoff",
        "soundpressplgin", "spbtn", "spi", "split", "stop", "stop2", "stralias", "sub", "systemcall", "texec",
        "textclear", "textexbtn", "textoff", "texton", "textspeed", "time", "transmode", "trap", "trap2", "underline",
        "versionstr", "voicevol", "vsp", "vsp2", "wait", "waittimer", "wave", "waveloop", "wavestop", "windowback",
        "windoweffect", "zenkakko",
    ]

    /// 每个语句开头的命令名（文字行、注释、标签跳过；if 后面的命令不细分）。
    static func 用到的未支持命令(_ script: NScripter脚本) -> Set<String> {
        var used = Set<String>()
        var defined = Set<String>()
        for line in script.行 {
            let chars = Array(line.unicodeScalars)
            var i = 0
            statements: while i < chars.count {
                while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
                guard i < chars.count else { break }
                let c = chars[i]
                if c == ":" { i += 1; continue }
                guard c.isASCII, c.properties.isAlphabetic || c == "_" else { break statements }
                let start = i
                while i < chars.count, chars[i].isASCII, chars[i].properties.isAlphabetic || chars[i] == "_" || ("0"..."9").contains(chars[i]) { i += 1 }
                let name = String(String.UnicodeScalarView(chars[start..<i])).lowercased()
                used.insert(name)
                var quoted = false
                let argumentStart = i
                while i < chars.count {
                    if chars[i] == "\"" { quoted.toggle() } else if !quoted, chars[i] == ":" || chars[i] == ";" { break }
                    i += 1
                }
                if name == "defsub" {
                    let argument = String(String.UnicodeScalarView(chars[argumentStart..<i]))
                    let defsub = argument.drop { $0 == " " || $0 == "\t" }.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    defined.insert(defsub.lowercased())
                }
                if i < chars.count, chars[i] == ";" { break }
            }
        }
        return used.subtracting(已支持命令).subtracting(defined)
    }
}
