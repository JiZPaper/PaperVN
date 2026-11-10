import Siglus
import SwiftUI
import UIKit

/// SiglusEngine 的视觉小说，由 siglus_rs（MPL-2.0）运行。
/// siglus_rs 用 wgpu 画在 CAMetalLayer 上，所以画面只能包一个 UIView；其余界面都在 SwiftUI 里。
@MainActor
@Observable
final class Siglus运行控制 {
    /// 游戏弹出的系统对话框（例如“要结束游戏吗？”），由 SwiftUI 显示
    struct 系统对话框: Identifiable {
        let id: UInt64
        let 类型: Int32
        let 标题: String
        let 内容: String
    }

    let 项目目录: URL
    private(set) var 已结束 = false
    private(set) var 错误: String?
    var 对话框: 系统对话框?
    var 快进 = false {
        didSet {
            guard 快进 != oldValue else { return }
            // Siglus 按住 Ctrl 快进
            if 快进 { 视图?.按下(0x11) } else { 视图?.松开(0x11) }
        }
    }

    fileprivate weak var 视图: Siglus画面视图?

    init(项目目录: URL) {
        self.项目目录 = 项目目录
    }

    /// 和右键一样打开游戏自己的系统菜单（保存、加载、设置、历史记录都在里面）
    func 打开菜单() {
        视图?.按下(0x1B)
        视图?.松开(0x1B)
    }

    func 暂停(_ paused: Bool) {
        视图?.暂停 = paused
    }

    /// 类型 0：好；1：好/取消；2：是/否；3：是/否/取消。值是按钮的序号。
    func 回答(_ value: Int64) {
        guard let dialog = 对话框 else { return }
        对话框 = nil
        视图?.回答(dialog.id, value)
    }

    fileprivate func 结束() { 已结束 = true }
    fileprivate func 出错(_ message: String) { 错误 = message }

    /// 脚本用了游戏自己的密钥、文件夹里又没有可用的 key.toml 时（需要适配模拟器的版本），
    /// siglus_ios_create 会在主线程上暴力推算十几分钟以上，这时不运行。
    nonisolated static func 检查密钥(_ project: URL) throws {
        switch project.path.withCString({ papervn_siglus_key_status($0) }) {
        case 0: return
        case 1: throw 视觉小说运行错误.无法读取(String(localized: "此视觉小说的脚本已加密，PaperVN无法读取。"))
        default: throw 视觉小说运行错误.无法读取(String(localized: "无法读取此视觉小说的脚本。"))
        }
    }
}

struct Siglus视图: UIViewRepresentable {
    let 控制: Siglus运行控制

    func makeUIView(context: Context) -> Siglus画面视图 {
        let view = Siglus画面视图(控制: 控制)
        控制.视图 = view
        return view
    }

    func updateUIView(_ uiView: Siglus画面视图, context: Context) {}

    static func dismantleUIView(_ uiView: Siglus画面视图, coordinator: ()) {
        uiView.销毁()
    }
}

final class Siglus画面视图: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    private weak var 控制: Siglus运行控制?
    private let 项目目录: String
    private var handle: UnsafeMutableRawPointer?
    private var displayLink: CADisplayLink?
    private var 上一帧: CFTimeInterval?
    private var 画面像素 = (0 as UInt32, 0 as UInt32)
    private var 逻辑尺寸 = CGSize(width: 1280, height: 720)
    /// 游戏画面在视图里的位置（点），触摸坐标按它换算
    private var 画面范围 = CGRect.zero
    var 暂停 = false {
        didSet { 上一帧 = nil }
    }

    init(控制: Siglus运行控制) {
        self.控制 = 控制
        项目目录 = 控制.项目目录.path
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(下一帧(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            上一帧 = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        let metal = layer as! CAMetalLayer
        metal.contentsScale = scale
        let width = UInt32(max(1, (size.width * scale).rounded()))
        let height = UInt32(max(1, (size.height * scale).rounded()))
        metal.drawableSize = CGSize(width: CGFloat(width), height: CGFloat(height))

        if handle == nil {
            创建(width, height, scale)
        } else if (width, height) != 画面像素 {
            画面像素 = (width, height)
            调整画面(scale)
        }
    }

    private func 创建(_ width: UInt32, _ height: UInt32, _ scale: Double) {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        handle = 项目目录.withCString { siglus_ios_create(pointer, width, height, scale, $0) }
        guard let handle else {
            控制?.出错(String(localized: "无法运行此视觉小说。"))
            return
        }
        画面像素 = (width, height)
        var logicalWidth: UInt32 = 1280
        var logicalHeight: UInt32 = 720
        siglus_ios_logical_size(handle, &logicalWidth, &logicalHeight)
        逻辑尺寸 = CGSize(width: Double(max(1, logicalWidth)), height: Double(max(1, logicalHeight)))
        调整画面(scale)
        siglus_ios_set_native_messagebox_callback(handle, { userData, requestID, kind, title, message in
            guard let userData else { return }
            let title = title.map { String(cString: $0) } ?? ""
            let message = message.map { String(cString: $0) } ?? ""
            nonisolated(unsafe) let pointer = userData
            Task { @MainActor in
                let view = Unmanaged<Siglus画面视图>.fromOpaque(pointer).takeUnretainedValue()
                view.控制?.对话框 = .init(id: requestID, 类型: kind, 标题: title, 内容: message)
            }
        }, pointer)
    }

    /// 按比例放进视图，四周留黑边
    private func 调整画面(_ scale: Double) {
        guard let handle else { return }
        let (width, height) = 画面像素
        let fit = min(Double(width) / 逻辑尺寸.width, Double(height) / 逻辑尺寸.height)
        let viewportWidth = UInt32(max(1, min(Double(width), (逻辑尺寸.width * fit).rounded())))
        let viewportHeight = UInt32(max(1, min(Double(height), (逻辑尺寸.height * fit).rounded())))
        let x = (width - viewportWidth) / 2
        let y = (height - viewportHeight) / 2
        siglus_ios_resize_viewport(handle, width, height, x, y, viewportWidth, viewportHeight)
        画面范围 = CGRect(
            x: Double(x) / scale, y: Double(y) / scale,
            width: Double(viewportWidth) / scale, height: Double(viewportHeight) / scale
        )
    }

    @objc private func 下一帧(_ link: CADisplayLink) {
        guard let handle, !暂停 else { return }
        let elapsed = 上一帧.map { link.timestamp - $0 } ?? link.duration
        上一帧 = link.timestamp
        let milliseconds = UInt32((min(max(elapsed, 0), 0.2) * 1000).rounded())
        switch siglus_ios_step(handle, milliseconds) {
        case 0:
            break
        case 1:
            displayLink?.invalidate()
            displayLink = nil
            控制?.结束()
        default:
            displayLink?.invalidate()
            displayLink = nil
            控制?.出错(String(localized: "此视觉小说意外退出。"))
        }
    }

    func 按下(_ code: Int32) {
        guard let handle else { return }
        siglus_ios_key_down(handle, code)
    }

    func 松开(_ code: Int32) {
        guard let handle else { return }
        siglus_ios_key_up(handle, code)
    }

    func 回答(_ id: UInt64, _ value: Int64) {
        guard let handle else { return }
        siglus_ios_submit_messagebox_result(handle, id, value)
    }

    func 销毁() {
        displayLink?.invalidate()
        displayLink = nil
        guard let handle else { return }
        siglus_ios_set_native_messagebox_callback(handle, nil, nil)
        siglus_ios_destroy(handle)
        self.handle = nil
    }

    // MARK: 触摸（phase：0 按下、1 移动、2 松开、3 取消）

    private func 发送(_ phase: Int32, _ touches: Set<UITouch>) {
        guard let handle, let touch = touches.first, 画面范围.width > 0 else { return }
        let point = touch.location(in: self)
        let x = (point.x - 画面范围.minX) * 逻辑尺寸.width / 画面范围.width
        let y = (point.y - 画面范围.minY) * 逻辑尺寸.height / 画面范围.height
        siglus_ios_touch(handle, phase, x, y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { 发送(0, touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { 发送(1, touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { 发送(2, touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { 发送(3, touches) }
}
