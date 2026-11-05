import KiriKiri
import Siglus
import SwiftUI
import UIKit

/// RealLive、AVG32、UK2 的视觉小说，由 siglus_rs（MPL-2.0）运行。
/// 这几个引擎不画 Metal，每帧给一张 RGBA 图，由这里显示并转发点按和按键。
@MainActor
@Observable
final class 帧缓冲游戏控制 {
    let 游戏目录: URL
    let 引擎: String
    private(set) var 已结束 = false
    private(set) var 错误: String?
    var 快进 = false {
        didSet {
            guard 快进 != oldValue, let handle else { return }
            game_fb_key(handle, 按键.ctrl, 快进 ? 1 : 0)
        }
    }
    fileprivate var 暂停中 = false
    fileprivate var handle: OpaquePointer?

    /// game_fb_key 的按键编号
    private enum 按键 {
        static let esc: UInt32 = 2
        static let ctrl: UInt32 = 14
    }

    init(游戏目录: URL, 引擎: String) {
        self.游戏目录 = 游戏目录
        self.引擎 = 引擎
    }

    /// 和右键一样打开游戏自己的系统菜单
    func 打开菜单() {
        guard let handle else { return }
        game_fb_key(handle, 按键.esc, 1)
        game_fb_key(handle, 按键.esc, 0)
    }

    func 辅助点按() {
        guard let handle else { return }
        game_fb_pointer_button(handle, 1, 1)
        game_fb_pointer_button(handle, 1, 0)
    }

    func 暂停(_ paused: Bool) { 暂停中 = paused }

    fileprivate func 打开() {
        guard handle == nil, 错误 == nil else { return }
        // 这几个引擎默认找桌面系统的字体路径，iOS 上要明确给一个
        _ = (KiriKiri资源.路径 as NSString).appendingPathComponent("NotoSansCJK-Regular.ttc").withCString { game_add_font_file($0) }
        var failure: UnsafeMutablePointer<CChar>?
        handle = 游戏目录.path.withCString { root in
            引擎.withCString { engine in game_fb_open(root, engine, nil, &failure) }
        }
        if handle == nil {
            let detail = failure.map { String(cString: $0) } ?? ""
            if let failure { game_string_free(failure) }
            错误 = String(format: String(localized: "无法运行此视觉小说：%@"), detail)
        }
    }

    fileprivate func 结束() { 已结束 = true }

    fileprivate func 关闭() {
        guard let handle else { return }
        self.handle = nil
        game_fb_close(handle)
    }
}

struct 帧缓冲游戏视图: UIViewRepresentable {
    let 控制: 帧缓冲游戏控制

    func makeUIView(context: Context) -> 帧缓冲画面视图 { 帧缓冲画面视图(控制: 控制) }
    func updateUIView(_ uiView: 帧缓冲画面视图, context: Context) {}
    static func dismantleUIView(_ uiView: 帧缓冲画面视图, coordinator: ()) { uiView.停止() }
}

final class 帧缓冲画面视图: UIView {
    private let 控制: 帧缓冲游戏控制
    private var 画面循环: CADisplayLink?
    private var 上一帧: CFTimeInterval?
    private var 画面尺寸 = CGSize.zero

    init(控制: 帧缓冲游戏控制) {
        self.控制 = 控制
        super.init(frame: .zero)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, 画面循环 == nil else { return }
        控制.打开()
        let link = CADisplayLink(target: self, selector: #selector(下一帧))
        link.add(to: .main, forMode: .common)
        画面循环 = link
    }

    func 停止() {
        画面循环?.invalidate()
        画面循环 = nil
        控制.关闭()
    }

    @objc private func 下一帧(_ link: CADisplayLink) {
        guard let handle = 控制.handle else { return }
        let now = link.timestamp
        defer { 上一帧 = now }
        guard !控制.暂停中 else { return }
        let elapsed = 上一帧.map { now - $0 } ?? 0
        if game_fb_step(handle, UInt32(min(elapsed, 0.25) * 1000)) != 0 {
            画面循环?.invalidate()
            画面循环 = nil
            控制.结束()
            return
        }
        var width: UInt32 = 0, height: UInt32 = 0
        guard let pixels = game_fb_frame(handle, &width, &height), width > 0, height > 0,
              let data = CFDataCreate(nil, pixels, Int(width) * Int(height) * 4),
              let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: Int(width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return }
        画面尺寸 = CGSize(width: Int(width), height: Int(height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }

    /// 视图坐标换成游戏画面的像素坐标（画面按比例居中）
    private func 发送位置(_ touch: UITouch) {
        guard let handle = 控制.handle, 画面尺寸.width > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / 画面尺寸.width, bounds.height / 画面尺寸.height)
        let origin = CGPoint(x: (bounds.width - 画面尺寸.width * scale) / 2, y: (bounds.height - 画面尺寸.height * scale) / 2)
        let point = touch.location(in: self)
        game_fb_pointer_move(handle, Int32((point.x - origin.x) / scale), Int32((point.y - origin.y) / scale))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let handle = 控制.handle else { return }
        发送位置(touch)
        game_fb_pointer_button(handle, 0, 1)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { 发送位置(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let handle = 控制.handle else { return }
        发送位置(touch)
        game_fb_pointer_button(handle, 0, 0)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let handle = 控制.handle else { return }
        game_fb_pointer_button(handle, 0, 0)
    }
}

/// siglus_rs 把存档写到游戏目录下的 savedata_rs。不写进用户的游戏文件夹：
/// 在 PaperVN 的数据文件夹里用符号链接映射游戏文件，存档就留在 App 里。
nonisolated enum 帧缓冲项目目录 {
    static func 准备(游戏根目录 root: URL, 数据文件夹: URL) throws -> URL {
        let manager = FileManager.default
        let mapped = 数据文件夹.appending(path: "帧缓冲游戏", directoryHint: .isDirectory)
        try manager.createDirectory(at: mapped, withIntermediateDirectories: true)
        for name in try manager.contentsOfDirectory(atPath: mapped.path) where name != "savedata_rs" {
            try? manager.removeItem(at: mapped.appending(path: name))
        }
        for entry in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            guard entry.lastPathComponent.lowercased() != "savedata_rs" else { continue }
            try manager.createSymbolicLink(at: mapped.appending(path: entry.lastPathComponent), withDestinationURL: entry)
        }
        return mapped
    }
}

/// 用 siglus_rs 的判断区分 RealLive、AVG32 和 UK2：只看文件名分不清
nonisolated enum 帧缓冲引擎识别 {
    static func 引擎(_ url: URL) -> 视觉小说引擎? {
        guard let pointer = url.path.withCString({ game_probe_json($0, nil, nil) }) else { return nil }
        defer { game_string_free(pointer) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8)) as? [String: Any],
              let engine = object["engine"] as? String else { return nil }
        switch engine {
        case "reallive": return .realLive
        case "avg32": return .avg32
        case "uk2": return .uk2
        default: return nil
        }
    }
}
