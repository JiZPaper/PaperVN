import SwiftUI
import WebKit

/// 网页引擎的视觉小说。iOS 26 起用 SwiftUI 的 WebView；iOS 18 只能退回 WKWebView。
struct 网页游戏视图: View {
    let 资源: 网页游戏资源
    let vnID: String

    var body: some View {
        if #available(iOS 26.0, *) {
            网页游戏SwiftUI视图(资源: 资源, vnID: vnID)
        } else {
            网页游戏兼容视图(资源: 资源, vnID: vnID)
        }
    }

    /// 关掉文字选择、长按菜单和回弹，让页面像 App 一样响应触摸。
    fileprivate static let 注入脚本 = """
    (function() {
      var style = document.createElement('style');
      style.textContent = 'html,body{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;overscroll-behavior:none;touch-action:manipulation;}html{background:#000;}';
      (document.head || document.documentElement).appendChild(style);
      window.open = function() { return null; };
    })();
    """
}

// MARK: - iOS 26

@available(iOS 26.0, *)
private struct 网页游戏SwiftUI视图: View {
    let 资源: 网页游戏资源
    let vnID: String
    @State private var page: WebPage?

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewTextSelection(.disabled)
                    .webViewContentBackground(.hidden)
            } else {
                Color.black
            }
        }
        .task(id: vnID) {
            var configuration = WebPage.Configuration()
            configuration.urlSchemeHandlers[URLScheme(网页游戏资源.scheme)!] = 网页游戏scheme处理(资源: 资源)
            configuration.mediaPlaybackBehavior = .allowsInlinePlayback
            configuration.userContentController.addUserScript(WKUserScript(
                source: 网页游戏视图.注入脚本, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
            let page = WebPage(configuration: configuration)
            #if DEBUG
            page.isInspectable = true
            #endif
            self.page = page
            let url = 网页游戏资源.入口URL(作品: vnID, 入口: 资源.入口)
            do {
                for try await _ in page.load(URLRequest(url: url)) {}
            } catch {
                // 加载失败时页面本身会显示错误，这里不需要处理
            }
        }
    }
}

@available(iOS 26.0, *)
private struct 网页游戏scheme处理: URLSchemeHandler {
    let 资源: 网页游戏资源

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        let resource = 资源
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let (response, data) = resource.回应(request)
                continuation.yield(.response(response))
                if !data.isEmpty { continuation.yield(.data(data)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - iOS 18

private struct 网页游戏兼容视图: UIViewRepresentable {
    let 资源: 网页游戏资源
    let vnID: String

    func makeCoordinator() -> 网页游戏兼容scheme处理 {
        网页游戏兼容scheme处理(资源: 资源)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: 网页游戏资源.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(
            source: 网页游戏视图.注入脚本, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: 网页游戏资源.入口URL(作品: vnID, 入口: 资源.入口)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

final class 网页游戏兼容scheme处理: NSObject, WKURLSchemeHandler {
    private let 资源: 网页游戏资源
    private var 已停止: Set<ObjectIdentifier> = []

    init(资源: 网页游戏资源) {
        self.资源 = 资源
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        let request = urlSchemeTask.request
        let resource = 资源
        nonisolated(unsafe) let task = urlSchemeTask
        Task {
            let (response, data) = await Task.detached(priority: .userInitiated) {
                resource.回应(request)
            }.value
            // WebKit 停止过的任务再回应会抛出异常
            guard !self.已停止.contains(id) else {
                self.已停止.remove(id)
                return
            }
            task.didReceive(response)
            if !data.isEmpty { task.didReceive(data) }
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        已停止.insert(ObjectIdentifier(urlSchemeTask))
    }
}
