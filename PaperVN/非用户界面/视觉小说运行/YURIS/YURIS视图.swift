import AVFoundation
import KiriKiri
import SwiftUI
import UIKit

/// Ogg Vorbis：解码器在 KiriKiri 的库里（libvorbisfile）
nonisolated final class YURISOgg流: YURIS音频流 {
    let 采样率: Double
    let 声道数: Int
    let 总帧数: Int64
    private let 数据: UnsafeMutableRawPointer
    private let 句柄: OpaquePointer

    init?(data: Data) {
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 1)
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count)
        guard let handle = papervn_ogg_open(bytes, data.count) else {
            bytes.deallocate()
            return nil
        }
        数据 = bytes
        句柄 = handle
        采样率 = papervn_ogg_sample_rate(handle)
        声道数 = Int(papervn_ogg_channels(handle))
        总帧数 = papervn_ogg_total_frames(handle)
    }

    deinit {
        papervn_ogg_close(句柄)
        数据.deallocate()
    }

    func 读取(_ buffer: UnsafeMutablePointer<Float>, 帧数: Int) -> Int {
        Int(papervn_ogg_read(句柄, buffer, Int64(帧数)))
    }

    func 定位(_ frame: Int64) {
        papervn_ogg_seek(句柄, frame)
    }
}

/// 把虚拟机放在自己的线程上跑，界面只拿最新一帧和转发输入
@MainActor
@Observable
final class YURIS运行控制 {
    struct 对话框内容: Identifiable {
        let id = UUID()
        let 请求: YURIS对话框请求
    }

    let 游戏目录: URL
    let 存档目录: URL
    private(set) var 已结束 = false
    private(set) var 错误: String?
    var 对话框: 对话框内容?
    var 快进 = false {
        didSet {
            guard 快进 != oldValue else { return }
            运行器?.输入.按键(YURIS输入状态.控制键, 按下: 快进)
        }
    }
    @ObservationIgnored fileprivate var 运行器: YURIS运行器?
    @ObservationIgnored fileprivate let 媒体 = YURIS界面媒体()

    init(游戏目录: URL, 存档目录: URL) {
        self.游戏目录 = 游戏目录
        self.存档目录 = 存档目录
    }

    fileprivate func 打开() {
        guard 运行器 == nil, 错误 == nil else { return }
        let runner = YURIS运行器(游戏目录: 游戏目录, 存档目录: 存档目录, 媒体: YURIS媒体桥(界面: 媒体))
        runner.结束回调 = { [weak self] message in
            Task { @MainActor in
                if let message {
                    self?.错误 = message
                } else {
                    self?.已结束 = true
                }
            }
        }
        runner.对话框回调 = { [weak self] request, answer in
            Task { @MainActor in
                guard let self else {
                    answer(1)
                    return
                }
                self.待回答 = answer
                self.对话框 = 对话框内容(请求: request)
            }
        }
        运行器 = runner
        runner.启动()
    }

    @ObservationIgnored private var 待回答: ((Int) -> Void)?

    func 回答(_ value: Int) {
        对话框 = nil
        待回答?(value)
        待回答 = nil
    }

    fileprivate func 关闭() {
        运行器?.停止()
        运行器 = nil
        媒体.全部关闭()
        待回答?(2)
        待回答 = nil
    }

    func 暂停(_ paused: Bool) { 运行器?.暂停(paused) }

    /// 右键：游戏自己的系统菜单
    func 辅助点按() {
        运行器?.输入.点按(YURIS输入状态.右键)
    }

    /// 请求退出：走游戏自己的“关闭窗口”流程（会弹确认）
    func 请求关闭() {
        运行器?.请求关闭()
    }
}

/// 运行线程
nonisolated final class YURIS运行器: @unchecked Sendable {
    let 输入 = YURIS输入状态()
    private let 游戏目录: URL
    private let 存档目录: URL
    private let lock = NSLock()
    private var 最新帧: CGImage?
    private var 帧序号 = 0
    private var 画面大小 = CGSize(width: 1, height: 1)
    private var 已停止 = false
    private var 已暂停 = false
    private var 线程: Thread?
    private var 虚拟机: YURIS虚拟机?
    private var 要关闭 = false
    private let 媒体: YURIS媒体桥
    var 结束回调: ((String?) -> Void)?
    var 对话框回调: ((YURIS对话框请求, @escaping (Int) -> Void) -> Void)?

    init(游戏目录: URL, 存档目录: URL, 媒体: YURIS媒体桥) {
        self.游戏目录 = 游戏目录
        self.存档目录 = 存档目录
        self.媒体 = 媒体
        FFmpeg影片后端.启用()
    }

    func 启动() {
        let thread = Thread { [weak self] in self?.主循环() }
        thread.name = "YU-RIS"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 4 << 20
        线程 = thread
        thread.start()
    }

    func 停止() {
        lock.lock()
        已停止 = true
        lock.unlock()
    }

    func 暂停(_ paused: Bool) {
        lock.lock()
        已暂停 = paused
        lock.unlock()
    }

    func 请求关闭() {
        lock.lock()
        要关闭 = true
        lock.unlock()
    }

    func 取最新帧() -> (CGImage, Int, CGSize)? {
        lock.lock()
        defer { lock.unlock() }
        guard let image = 最新帧 else { return nil }
        return (image, 帧序号, 画面大小)
    }

    private func 建立虚拟机(声音: YURIS声音) throws -> YURIS虚拟机 {
        let resources = YURIS资源库(根目录: 游戏目录)
        let program = try YURIS程序(资源: resources)
        let vm = try YURIS虚拟机(程序: program, 存档目录: 存档目录, 声音: 声音)
        vm.输入状态 = 输入
        vm.Flash接口 = 媒体
        vm.MIDI接口 = 媒体
        vm.对话框 = { [weak self] request in
            guard let self, let callback = self.对话框回调 else { return 1 }
            // 脚本要等回答才能往下走
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var answer = 1
            callback(request) { value in
                answer = value
                semaphore.signal()
            }
            semaphore.wait()
            return answer
        }
        #if DEBUG
        vm.日志 = { print("[YU-RIS] \($0)") }
        #endif
        return vm
    }

    private func 主循环() {
        // 声音会话和其他引擎一样：播放类别，不被静音开关影响
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let sound = YURIS声音(ogg解码: { YURISOgg流(data: $0) }, 使用引擎: true)
        let vm: YURIS虚拟机
        do {
            vm = try 建立虚拟机(声音: sound)
        } catch {
            结束回调?(error.localizedDescription)
            return
        }
        虚拟机 = vm
        var current = vm
        var next = Date()
        let interval = 1.0 / 60
        while true {
            lock.lock()
            let stopped = 已停止, paused = 已暂停, close = 要关闭
            要关闭 = false
            lock.unlock()
            if stopped { break }
            if paused {
                sound.暂停引擎(true)
                current.暂停影片(true)
                while true {
                    Thread.sleep(forTimeInterval: 0.05)
                    lock.lock()
                    let keepWaiting = 已暂停 && !已停止
                    lock.unlock()
                    if !keepWaiting { break }
                }
                sound.暂停引擎(false)
                current.暂停影片(false)
                next = Date()
                continue
            }
            if close {
                // @_WINDOW_EXEC_CLOSE：脚本自己决定要不要退出
                current.全局[97]?.标量 = .整数(1)
            }
            autoreleasepool {
                current.运行一帧()
                if let canvas = current.画面.合成帧(), let image = YURIS画面.输出CGImage(canvas) {
                    let size = CGSize(width: canvas.宽, height: canvas.高)
                    lock.lock()
                    最新帧 = image
                    帧序号 += 1
                    画面大小 = size
                    lock.unlock()
                }
            }
            if current.已结束 {
                if current.请求重启, let restarted = try? 建立虚拟机(声音: sound) {
                    current.结束影片()
                    sound.全部停止()
                    current = restarted
                    虚拟机 = restarted
                    next = Date()
                    continue
                }
                break
            }
            next = next.addingTimeInterval(interval)
            let wait = next.timeIntervalSinceNow
            if wait > 0 {
                Thread.sleep(forTimeInterval: wait)
            } else if wait < -0.25 {
                next = Date()
            }
        }
        current.结束影片()
        sound.全部停止()
        current.画面.清空缓存()
        虚拟机 = nil
        lock.lock()
        let stoppedByUser = 已停止
        lock.unlock()
        if !stoppedByUser { 结束回调?(nil) }
    }
}

struct YURIS游戏视图: UIViewRepresentable {
    let 控制: YURIS运行控制

    func makeUIView(context: Context) -> YURIS画面视图 { YURIS画面视图(控制: 控制) }
    func updateUIView(_ uiView: YURIS画面视图, context: Context) {}
    static func dismantleUIView(_ uiView: YURIS画面视图, coordinator: ()) { uiView.停止() }
}

final class YURIS画面视图: UIView {
    private let 控制: YURIS运行控制
    private var 画面循环: CADisplayLink?
    private var 已显示序号 = -1
    private var 画面尺寸 = CGSize.zero

    init(控制: YURIS运行控制) {
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
        控制.媒体.容器 = self
        控制.媒体.轻点回调 = { [weak self] point in self?.轻点Flash(point) }
        let link = CADisplayLink(target: self, selector: #selector(下一帧))
        link.add(to: .main, forMode: .common)
        画面循环 = link
    }

    func 停止() {
        画面循环?.invalidate()
        画面循环 = nil
        控制.关闭()
    }

    @objc private func 下一帧() {
        guard let (image, sequence, size) = 控制.运行器?.取最新帧(), sequence != 已显示序号 else { return }
        已显示序号 = sequence
        画面尺寸 = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        控制.媒体.布局()
    }

    private func 轻点Flash(_ point: CGPoint) {
        发送位置(point)
        控制.运行器?.输入.点按(YURIS输入状态.左键)
    }

    private func 发送位置(_ touch: UITouch) {
        发送位置(touch.location(in: self))
    }

    /// 视图坐标换成游戏坐标（画面按比例居中）
    private func 发送位置(_ point: CGPoint) {
        guard let input = 控制.运行器?.输入, 画面尺寸.width > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / 画面尺寸.width, bounds.height / 画面尺寸.height)
        let origin = CGPoint(x: (bounds.width - 画面尺寸.width * scale) / 2, y: (bounds.height - 画面尺寸.height * scale) / 2)
        input.移动鼠标(x: Int((point.x - origin.x) / scale), y: Int((point.y - origin.y) / scale))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // 按住 Ctrl 时游戏不响应选项，轻点屏幕就结束快进
        if 控制.快进 { 控制.快进 = false }
        发送位置(touch)
        控制.运行器?.输入.按键(YURIS输入状态.左键, 按下: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { 发送位置(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { 发送位置(touch) }
        控制.运行器?.输入.按键(YURIS输入状态.左键, 按下: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        控制.运行器?.输入.按键(YURIS输入状态.左键, 按下: false)
    }
}
