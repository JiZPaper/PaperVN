import AVFoundation
import SwiftUI

/// NScripter 的画面。坐标都按游戏的逻辑分辨率（640×480 等）乘以缩放比例计算，文字按实际大小排版，不会因为放大而模糊。
struct NScripter视图: View {
    let 解释器: NScripter解释器
    @State private var 按下位置: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let width = CGFloat(解释器.屏幕宽)
            let height = CGFloat(解释器.屏幕高)
            let scale = min(proxy.size.width / width, proxy.size.height / height)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    NScripter场景层(解释器: 解释器, 场景: 解释器.显示场景, 缩放: scale)
                        .id(解释器.场景版本)
                        .zIndex(Double(解释器.场景版本))
                        .transition(.asymmetric(insertion: 过渡(解释器.过渡类型), removal: .identity))
                }
                .modifier(NScripter色调(单色: 解释器.显示场景.单色, 反色: 解释器.显示场景.反色))

                按钮按下层(scale)

                if 解释器.文本框可见 {
                    NScripter文本框层(解释器: 解释器, 缩放: scale)
                        .transition(.opacity)
                }
            }
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .offset(x: 解释器.震动偏移.width * scale, y: 解释器.震动偏移.height * scale)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        按下位置 = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                    }
                    .onEnded { value in
                        按下位置 = nil
                        guard abs(value.translation.width) < 30, abs(value.translation.height) < 30 else { return }
                        解释器.轻点(CGPoint(x: value.location.x / scale, y: value.location.y / scale))
                    }
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .animation(.easeOut(duration: 0.2), value: 解释器.文本框可见)
        }
        .background(Color.black)
        .overlay {
            if let player = 解释器.内置影片 {
                NScripter内置影片视图(影片: player) { 解释器.影片结束() }
                    .ignoresSafeArea()
                    .id(ObjectIdentifier(player))
            } else if let url = 解释器.影片 {
                NScripter影片视图(地址: url) { 解释器.影片结束() }
                    .ignoresSafeArea()
                    .id(url)
            }
        }
    }

    /// NScripter 的效果编号：2～9 百叶窗与帷幕（这里都按方向揭开），11～14 卷动，其余淡入淡出。
    private func 过渡(_ type: Int) -> AnyTransition {
        switch type {
        case 1: .identity
        case 2, 6: .modifier(active: NScripter揭开(进度: 0, 方向: .leading), identity: NScripter揭开(进度: 1, 方向: .leading))
        case 3, 7: .modifier(active: NScripter揭开(进度: 0, 方向: .trailing), identity: NScripter揭开(进度: 1, 方向: .trailing))
        case 4, 8: .modifier(active: NScripter揭开(进度: 0, 方向: .top), identity: NScripter揭开(进度: 1, 方向: .top))
        case 5, 9: .modifier(active: NScripter揭开(进度: 0, 方向: .bottom), identity: NScripter揭开(进度: 1, 方向: .bottom))
        case 11: .move(edge: .trailing)
        case 12: .move(edge: .leading)
        case 13: .move(edge: .bottom)
        case 14: .move(edge: .top)
        default: .opacity
        }
    }

    @ViewBuilder
    private func 按钮按下层(_ scale: CGFloat) -> some View {
        if 解释器.等待 == .按钮, let point = 按下位置,
           let button = 解释器.按钮.first(where: { $0.区域.contains(point) }) {
            Group {
                if let rect = button.按下图像, let tag = 解释器.按钮图像,
                   let source = 解释器.图像(tag)?.格.first, let cropped = source.cropping(to: rect) {
                    Image(decorative: cropped, scale: 1)
                        .resizable()
                        .frame(width: button.区域.width * scale, height: button.区域.height * scale)
                } else if let number = button.精灵, let sprite = 解释器.显示场景.精灵[number],
                          let image = 解释器.图像(sprite.标签), image.格.count > 1 {
                    Image(decorative: image.格[1], scale: 1)
                        .resizable()
                        .frame(width: CGFloat(image.宽) * scale, height: CGFloat(image.高) * scale)
                } else {
                    Rectangle().fill(.white.opacity(0.15))
                        .frame(width: button.区域.width * scale, height: button.区域.height * scale)
                }
            }
            .offset(x: button.区域.minX * scale, y: button.区域.minY * scale)
            .allowsHitTesting(false)
        }
    }
}

private struct NScripter揭开: ViewModifier {
    let 进度: CGFloat
    let 方向: Edge

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                let size = proxy.size
                switch 方向 {
                case .leading:
                    Rectangle().frame(width: size.width * 进度).frame(maxWidth: .infinity, alignment: .leading)
                case .trailing:
                    Rectangle().frame(width: size.width * 进度).frame(maxWidth: .infinity, alignment: .trailing)
                case .top:
                    Rectangle().frame(height: size.height * 进度).frame(maxHeight: .infinity, alignment: .top)
                case .bottom:
                    Rectangle().frame(height: size.height * 进度).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

private struct NScripter色调: ViewModifier {
    let 单色: UInt32?
    let 反色: Bool

    func body(content: Content) -> some View {
        content
            .grayscale(单色 == nil ? 0 : 1)
            .colorMultiply(单色.map { Color(nscripter: $0) } ?? .white)
            .modifier(反色修饰(启用: 反色))
    }

    private struct 反色修饰: ViewModifier {
        let 启用: Bool
        func body(content: Content) -> some View {
            if 启用 { content.colorInvert() } else { content }
        }
    }
}

private struct NScripter场景层: View {
    let 解释器: NScripter解释器
    let 场景: NScripter场景
    let 缩放: CGFloat

    var body: some View {
        let layers = 分层
        ZStack(alignment: .topLeading) {
            if let color = 场景.背景颜色 {
                Color(nscripter: color)
            }
            if let tag = 场景.背景图像 {
                Color.black
                精灵视图(NScripter精灵(标签: tag, x: 0, y: 0))
            }
            ForEach(layers.下层, id: \.0) { 精灵视图($0.1) }
            ForEach(["l", "c", "r"], id: \.self) { position in
                if let sprite = 场景.立绘[position] { 精灵视图(sprite) }
            }
            ForEach(layers.上层, id: \.0) { 精灵视图($0.1) }
        }
        .frame(
            width: CGFloat(解释器.屏幕宽) * 缩放,
            height: CGFloat(解释器.屏幕高) * 缩放,
            alignment: .topLeading
        )
    }

    private var 分层: (下层: [(Int, NScripter精灵)], 上层: [(Int, NScripter精灵)]) {
        let sorted = 场景.精灵.sorted { $0.key > $1.key }
        let threshold = 499
        return (sorted.filter { $0.key >= threshold }.map { ($0.key, $0.value) },
                sorted.filter { $0.key < threshold }.map { ($0.key, $0.value) })
    }

    @ViewBuilder
    private func 精灵视图(_ sprite: NScripter精灵) -> some View {
        if sprite.可见, let image = 解释器.图像(sprite.标签) {
            let frame = image.格[min(max(0, sprite.格), image.格.count - 1)]
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: CGFloat(frame.width) * 缩放, height: CGFloat(frame.height) * 缩放)
                .opacity(Double(sprite.透明度) / 255)
                .offset(x: CGFloat(sprite.x) * 缩放, y: CGFloat(sprite.y) * 缩放)
        }
    }
}

private struct NScripter文本框层: View {
    let 解释器: NScripter解释器
    let 缩放: CGFloat
    @State private var 闪烁 = false

    var body: some View {
        let box = 解释器.文本框
        let pitch = CGFloat(box.字高 + box.行距) * 缩放
        ZStack(alignment: .topLeading) {
            窗口(box)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(解释器.页面.enumerated()), id: \.offset) { _, line in
                    行文字(line, box)
                        .frame(height: pitch, alignment: .topLeading)
                }
                if case .选择(let options) = 解释器.等待 {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            解释器.选择(index)
                        } label: {
                            Text(verbatim: option)
                                .font(字体(box))
                                .tracking(CGFloat(box.字距) * 缩放)
                                .fixedSize()
                                .frame(height: pitch, alignment: .topLeading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(NScripter选项样式(
                            选中: Color(nscripter: 解释器.选择颜色.选中),
                            未选中: Color(nscripter: 解释器.选择颜色.未选中)
                        ))
                    }
                }
            }
            .shadow(color: box.阴影 ? .black.opacity(0.9) : .clear, radius: 0, x: 缩放, y: 缩放)
            .offset(x: CGFloat(box.文字x) * 缩放, y: CGFloat(box.文字y) * 缩放)

            if case .点击(let page) = 解释器.等待 {
                Image(systemName: page ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: CGFloat(box.字宽) * 0.5 * 缩放))
                    .foregroundStyle(.white)
                    .opacity(闪烁 ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: 闪烁)
                    .onAppear { 闪烁 = true }
                    .onDisappear { 闪烁 = false }
                    .offset(
                        x: CGFloat(box.窗口x2 - box.字宽) * 缩放,
                        y: CGFloat(box.窗口y2 - box.字高) * 缩放
                    )
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(解释器.等待 != .无 && 是选择)
    }

    private var 是选择: Bool {
        if case .选择 = 解释器.等待 { return true }
        return false
    }

    @ViewBuilder
    private func 窗口(_ box: NScripter文本框) -> some View {
        let rect = CGRect(
            x: CGFloat(box.窗口x1) * 缩放, y: CGFloat(box.窗口y1) * 缩放,
            width: CGFloat(box.窗口x2 - box.窗口x1 + 1) * 缩放, height: CGFloat(box.窗口y2 - box.窗口y1 + 1) * 缩放
        )
        if let tag = box.窗口图像, let image = 解释器.图像(tag)?.格.first {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: CGFloat(image.width) * 缩放, height: CGFloat(image.height) * 缩放)
                .offset(x: rect.minX, y: rect.minY)
        } else if let color = box.窗口颜色 {
            // 和 NScripter 一样把窗口范围内的画面乘上窗口颜色
            Rectangle()
                .fill(Color(nscripter: color))
                .blendMode(.multiply)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    private func 字体(_ box: NScripter文本框) -> Font {
        let size = CGFloat(box.字宽) * 缩放
        if let name = 解释器.字体名 {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: box.粗体 ? .medium : .regular)
    }

    /// 一行里各段文字颜色不同：拼成一个 AttributedString（不用已弃用的 Text 相加，也不会变成要翻译的字符串）
    private func 行文字(_ line: [NScripter文字片段], _ box: NScripter文本框) -> some View {
        var attributed = AttributedString()
        for part in line {
            var piece = AttributedString(part.文字)
            piece.foregroundColor = Color(nscripter: part.颜色)
            attributed += piece
        }
        return Text(attributed)
            .font(字体(box))
            .tracking(CGFloat(box.字距) * 缩放)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct NScripter选项样式: ButtonStyle {
    let 选中: Color
    let 未选中: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? 选中 : 未选中)
    }
}

extension Color {
    init(nscripter value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

// MARK: - 存档与历史记录

struct NScripter存档页面: View {
    enum 存档模式 { case 保存, 加载 }

    let 解释器: NScripter解释器
    let 模式: 存档模式
    let 完成: () -> Void
    @State private var 刷新 = 0
    @State private var 替换位置: Int?

    var body: some View {
        NavigationStack {
            List {
                ForEach(1...NScripter解释器.存档数量, id: \.self) { slot in
                    let summary = 解释器.存档摘要(slot)
                    Button {
                        选择(slot, 已有: summary != nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: String(localized: "存档%lld"), slot))
                                    .font(.headline)
                                Spacer()
                                if let summary {
                                    Text(summary.时间, format: .dateTime.year().month().day().hour().minute())
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(verbatim: summary?.预览.isEmpty == false ? summary!.预览 : String(localized: "空"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(模式 == .加载 && summary == nil)
                    .swipeActions {
                        if summary != nil {
                            Button("删除", role: .destructive) {
                                解释器.删除存档(slot)
                                刷新 += 1
                            }
                        }
                    }
                }
            }
            .id(刷新)
            .navigationTitle(模式 == .保存 ? "保存" : "加载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        完成()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
            .confirmationDialog(
                "要替换此存档吗？",
                isPresented: Binding(get: { 替换位置 != nil }, set: { if !$0 { 替换位置 = nil } }),
                titleVisibility: .visible
            ) {
                Button("替换", role: .destructive) {
                    if let slot = 替换位置 { 保存(slot) }
                }
            }
        }
    }

    private func 选择(_ slot: Int, 已有: Bool) {
        switch 模式 {
        case .保存:
            if 已有 { 替换位置 = slot } else { 保存(slot) }
        case .加载:
            解释器.载入(slot)
            完成()
        }
    }

    private func 保存(_ slot: Int) {
        try? 解释器.存储(到: slot)
        完成()
    }
}

struct NScripter历史记录页面: View {
    let 解释器: NScripter解释器
    let 完成: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(解释器.回想.enumerated()), id: \.offset) { index, page in
                        Text(verbatim: page)
                            .id(index)
                    }
                }
                .onAppear { proxy.scrollTo(解释器.回想.count - 1, anchor: .bottom) }
            }
            .overlay {
                if 解释器.回想.isEmpty {
                    ContentUnavailableView("无历史记录", systemImage: "text.alignleft")
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        完成()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
    }
}

/// 全屏播放自己解码的影片（MPEG-1、AVI、WMV 等），轻点跳过
private struct NScripter内置影片视图: UIViewRepresentable {
    let 影片: 视觉小说影片
    let 结束: () -> Void

    func makeUIView(context: Context) -> 视图 { 视图(影片: 影片, 结束: 结束) }
    func updateUIView(_ uiView: 视图, context: Context) {}
    static func dismantleUIView(_ uiView: 视图, coordinator: ()) { uiView.停止() }

    final class 视图: UIView {
        private let 影片: 视觉小说影片
        private let 结束: () -> Void
        private var 画面循环: CADisplayLink?
        private var 观察: [NSObjectProtocol] = []
        private var 已结束 = false

        init(影片: 视觉小说影片, 结束: @escaping () -> Void) {
            self.影片 = 影片
            self.结束 = 结束
            super.init(frame: .zero)
            backgroundColor = .black
            layer.contentsGravity = .resizeAspect
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(跳过)))
            let center = NotificationCenter.default
            观察.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                影片.暂停(true)
            })
            观察.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                影片.暂停(false)
            })
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, 画面循环 == nil, !已结束 else { return }
            影片.开始()
            let link = CADisplayLink(target: self, selector: #selector(下一帧))
            link.add(to: .main, forMode: .common)
            画面循环 = link
        }

        @objc private func 下一帧() {
            if let frame = 影片.取帧(), let provider = CGDataProvider(data: Data(bytes: frame.像素, count: frame.宽 * frame.高 * 4) as CFData) {
                let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                let image = CGImage(width: frame.宽, height: frame.高, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.宽 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: info),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.contents = image
                CATransaction.commit()
            }
            if 影片.已结束 { 跳过() }
        }

        @objc private func 跳过() {
            guard !已结束 else { return }
            已结束 = true
            停止()
            结束()
        }

        func 停止() {
            画面循环?.invalidate()
            画面循环 = nil
            观察.forEach(NotificationCenter.default.removeObserver)
            观察 = []
            影片.停止()
        }
    }
}

/// 全屏播放影片，轻点跳过。放不了的格式马上结束。
private struct NScripter影片视图: UIViewRepresentable {
    let 地址: URL
    let 结束: () -> Void

    func makeUIView(context: Context) -> 视图 { 视图(地址: 地址, 结束: 结束) }
    func updateUIView(_ uiView: 视图, context: Context) {}
    static func dismantleUIView(_ uiView: 视图, coordinator: ()) { uiView.停止() }

    final class 视图: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private let 播放器: AVPlayer
        private var 观察: [NSObjectProtocol] = []
        private var 状态观察: NSKeyValueObservation?
        private let 结束: () -> Void
        private var 已结束 = false

        init(地址: URL, 结束: @escaping () -> Void) {
            let item = AVPlayerItem(url: 地址)
            播放器 = AVPlayer(playerItem: item)
            self.结束 = 结束
            super.init(frame: .zero)
            backgroundColor = .black
            (layer as? AVPlayerLayer)?.player = 播放器
            (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(跳过)))
            for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
                观察.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.跳过() }
                })
            }
            状态观察 = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async { self?.跳过() }
            }
            播放器.play()
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func 跳过() {
            guard !已结束 else { return }
            已结束 = true
            停止()
            结束()
        }

        func 停止() {
            播放器.pause()
            状态观察 = nil
            观察.forEach(NotificationCenter.default.removeObserver)
            观察 = []
        }
    }
}
