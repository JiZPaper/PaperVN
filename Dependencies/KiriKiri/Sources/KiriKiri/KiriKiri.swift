// krkr2 的 C 接口（papervn_kirikiri.h）。界面和驱动在 PaperVN 的视觉小说运行页面里。
@_exported import KiriKiriCore
import Foundation

public enum KiriKiri资源 {
    /// krkr2 自带界面（菜单、提示）用到的资源和默认字体
    public static var 路径: String {
        Bundle.module.resourceURL!.appending(path: "res", directoryHint: .isDirectory).path
    }

    /// MIDI 音色库（GeneralUser GS）。iOS 没有内置 GM 音色，播放 MIDI 必须自带
    public static var MIDI音色库: URL {
        Bundle.module.resourceURL!.appending(path: "soundfont/GeneralUser-GS.sf2", directoryHint: .notDirectory)
    }

    /// Ruffle（MIT / Apache 2.0）：用 WebAssembly 播放 swf，YU-RIS 的 FLASH 命令用
    public static var Ruffle目录: URL {
        Bundle.module.resourceURL!.appending(path: "ruffle", directoryHint: .isDirectory)
    }

    /// Ren'Py 官方的 WebAssembly 运行库（MIT，含的 LGPL 库见 LICENSE-renpy.txt）
    public static var RenPy运行库: URL {
        Bundle.module.resourceURL!.appending(path: "renpyweb", directoryHint: .isDirectory)
    }
}
