import KiriKiri
import UIKit
import WebKit

/// 虚拟机线程通过它控制界面上的 MIDI 和 Flash。调用按顺序转到主线程
nonisolated final class YURIS媒体桥: YURISFlash接口, YURISMIDI接口, @unchecked Sendable {
    private let 界面: YURIS界面媒体
    private let lock = NSLock()
    private var 播放中 = false
    private var 打开时间 = Date.distantPast
    private var 开始时间: Date?
    private var 暂停时间: Date?
    private var 帧率 = 0.0
    private var 总帧数 = 0
    private var 结束帧: Int?

    init(界面: YURIS界面媒体) {
        self.界面 = 界面
    }

    private func 主线程(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }

    func 播放(_ data: Data) {
        let 界面 = 界面
        主线程 { 界面.播放MIDI(data) }
    }

    func 停止() {
        let 界面 = 界面
        主线程 { 界面.停止MIDI() }
    }

    func 打开(地址: URL, x: Int, y: Int, 宽: Int, 高: Int, 画面宽: Int, 画面高: Int, 结束帧 end: Int?) {
        lock.lock()
        播放中 = true
        打开时间 = Date()
        开始时间 = nil
        暂停时间 = nil
        帧率 = 0
        总帧数 = 0
        结束帧 = end
        lock.unlock()
        let 界面 = 界面
        let area = CGRect(x: x, y: y, width: 宽, height: 高)
        let screen = CGSize(width: 画面宽, height: 画面高)
        主线程 { [weak self] in
            界面.打开Flash(地址, 区域: area, 画面: screen) { frames, rate in self?.收到元数据(frames, rate) }
        }
    }

    func 关闭() {
        lock.lock()
        播放中 = false
        lock.unlock()
        let 界面 = 界面
        主线程 { 界面.关闭Flash() }
    }

    func 暂停(_ paused: Bool) {
        lock.lock()
        if paused {
            暂停时间 = Date()
        } else if let start = 开始时间, let stopped = 暂停时间 {
            开始时间 = start.addingTimeInterval(Date().timeIntervalSince(stopped))
            暂停时间 = nil
        } else {
            暂停时间 = nil
        }
        lock.unlock()
        let 界面 = 界面
        主线程 { 界面.暂停媒体(paused) }
    }

    private func 收到元数据(_ frames: Int, _ rate: Double) {
        lock.lock()
        总帧数 = frames
        帧率 = rate
        开始时间 = Date()
        lock.unlock()
    }

    /// Ruffle 没有公开当前帧，按经过的时间和帧率估算
    var 状态: (播放中: Bool, 当前帧: Int, 总帧数: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard 播放中 else { return (false, 0, 总帧数) }
        guard let start = 开始时间 else {
            // Ruffle 没能打开这个文件时，不让脚本一直等下去
            if Date().timeIntervalSince(打开时间) > 15 { 播放中 = false }
            return (播放中, 0, 0)
        }
        let elapsed = (暂停时间 ?? Date()).timeIntervalSince(start)
        let frame = Int(elapsed * 帧率)
        let last = 结束帧 ?? 总帧数
        // 只有一帧的 swf 靠内部脚本播放，看不出什么时候结束，由游戏脚本决定
        if 总帧数 > 1, frame >= last {
            return (false, last, 总帧数)
        }
        return (true, 总帧数 > 1 ? frame : 0, 总帧数)
    }
}

/// 主线程上的 MIDI 播放器和 Flash 视图
@MainActor
final class YURIS界面媒体: NSObject {
    /// 游戏画面视图。Flash 按手册显示在所有图层最前面
    weak var 容器: UIView? {
        didSet { 布局() }
    }
    /// 轻点 Flash：既交给 swf，也告诉游戏（脚本常靠点按跳过）
    var 轻点回调: ((CGPoint) -> Void)?
    private var MIDI: MIDI播放器?
    private var 网页: WKWebView?
    private var 区域 = CGRect.zero
    private var 画面 = CGSize.zero
    private var 元数据回调: ((Int, Double) -> Void)?

    func 播放MIDI(_ data: Data) {
        MIDI?.停止()
        MIDI = MIDI播放器(数据: data, 循环: false)
        MIDI?.播放()
    }

    func 停止MIDI() {
        MIDI?.停止()
        MIDI = nil
    }

    func 暂停媒体(_ paused: Bool) {
        if paused { MIDI?.暂停() } else { MIDI?.播放() }
        网页?.evaluateJavaScript(paused ? "pause()" : "resume()")
    }

    func 打开Flash(_ file: URL, 区域 area: CGRect, 画面 screen: CGSize, 元数据: @escaping (Int, Double) -> Void) {
        关闭Flash()
        guard 视觉小说运行资源.已安装(.flash) else { return }
        区域 = area
        画面 = screen
        元数据回调 = 元数据
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(YURISFlash资源(影片: file), forURLScheme: "papervn-flash")
        configuration.userContentController.add(YURISFlash消息(self), name: "flash")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let tap = UITapGestureRecognizer(target: self, action: #selector(轻点(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        web.addGestureRecognizer(tap)
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        容器?.addSubview(web)
        网页 = web
        布局()
        web.load(URLRequest(url: URL(string: "papervn-flash://game/index.html")!))
    }

    func 关闭Flash() {
        网页?.configuration.userContentController.removeScriptMessageHandler(forName: "flash")
        网页?.removeFromSuperview()
        网页 = nil
        元数据回调 = nil
    }

    fileprivate func 收到消息(_ body: Any) {
        guard let info = body as? [String: Any] else { return }
        if let text = info["log"] as? String {
            #if DEBUG
            print("[Flash] \(text)")
            #endif
            return
        }
        guard let frames = info["frames"] as? Int else { return }
        #if DEBUG
        print("[Flash] 帧数 \(frames) 帧率 \(info["rate"] ?? "")")
        #endif
        元数据回调?(frames, (info["rate"] as? Double) ?? Double(info["rate"] as? Int ?? 0))
    }

    /// 画面在容器里按比例居中，和点按换算用同一套算法
    func 布局() {
        guard let web = 网页, let container = 容器, 画面.width > 0, 画面.height > 0 else { return }
        let bounds = container.bounds
        let scale = min(bounds.width / 画面.width, bounds.height / 画面.height)
        let x = (bounds.width - 画面.width * scale) / 2
        let y = (bounds.height - 画面.height * scale) / 2
        web.frame = CGRect(x: x + 区域.minX * scale, y: y + 区域.minY * scale,
                           width: 区域.width * scale, height: 区域.height * scale)
    }

    @objc private func 轻点(_ gesture: UITapGestureRecognizer) {
        guard let container = 容器 else { return }
        轻点回调?(gesture.location(in: container))
    }

    func 全部关闭() {
        停止MIDI()
        关闭Flash()
    }
}

extension YURIS界面媒体: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

/// 消息处理器会被 WebKit 强引用，所以中间隔一层
private final class YURISFlash消息: NSObject, WKScriptMessageHandler {
    weak var 目标: YURIS界面媒体?
    init(_ target: YURIS界面媒体) { 目标 = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        目标?.收到消息(message.body)
    }
}

/// 只提供 Ruffle 和这一个 swf
private final class YURISFlash资源: NSObject, WKURLSchemeHandler {
    private let 影片: URL

    init(影片: URL) {
        self.影片 = 影片
    }

    private static let 页面 = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
    <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
    ruffle-player{display:block;width:100%;height:100%}</style>
    <script>
    function report(t){try{window.webkit.messageHandlers.flash.postMessage({log:String(t)})}catch(e){}}
    window.addEventListener("error",e=>report("error "+e.message+" "+e.filename+":"+e.lineno));
    window.addEventListener("unhandledrejection",e=>report("rejection "+e.reason));
    for(const k of ["error","warn"]){const o=console[k];console[k]=(...a)=>{report(k+" "+a.join(" "));o.apply(console,a)}}
    </script>
    <script src="/ruffle/ruffle.js"></script></head><body><script>
    window.RufflePlayer.config={publicPath:"/ruffle/"};
    const element=window.RufflePlayer.newest().createPlayer();
    document.body.appendChild(element);
    const player=element.ruffle();
    element.addEventListener("loadedmetadata",()=>{
      const m=player.metadata;
      window.webkit.messageHandlers.flash.postMessage({frames:m.numFrames,rate:m.frameRate});
    });
    function pause(){player.suspend()}
    function resume(){player.resume()}
    player.load({url:"/movie.swf",autoplay:"on",unmuteOverlay:"hidden",splashScreen:false,
      contextMenu:"off",letterbox:"on",allowScriptAccess:false,warnOnUnsupportedContent:false,
      openUrlMode:"deny",allowNetworking:"none",logLevel:"error"});
    </script></body></html>
    """

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path
        var data: Data?
        var type = "application/octet-stream"
        if path == "/index.html" {
            data = Data(Self.页面.utf8)
            type = "text/html"
        } else if path == "/movie.swf" {
            data = try? Data(contentsOf: 影片, options: .mappedIfSafe)
            type = "application/x-shockwave-flash"
        } else if path.hasPrefix("/ruffle/"), !path.contains("..") {
            let file = 视觉小说运行资源.Ruffle目录.appending(path: String(path.dropFirst("/ruffle/".count)))
            data = try? Data(contentsOf: file, options: .mappedIfSafe)
            type = file.pathExtension == "wasm" ? "application/wasm" : "text/javascript"
        }
        guard let data else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            task.didFinish()
            return
        }
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": type, "Content-Length": String(data.count)])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
