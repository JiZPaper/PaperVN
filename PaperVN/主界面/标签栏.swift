import SwiftUI
import UIKit

enum PaperVNRootTab: Hashable {
    case today
    case library(用户列表筛选)
    case search
}

private enum PaperVNRootTabAccessibilityIdentifier {
    static let search = "PaperVN.RootTab.Search"
}

@available(iOS 18.0, *)
private func paperVNRootSearchTabRole(
    isIndependent: Bool,
    isPad: Bool = false
) -> TabRole? {
    if #available(iOS 27.0, *) {
        guard isIndependent else { return nil }
        return isPad ? .search : .prominent
    }
    return .search
}

struct TabBar: View {
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var urlRouter: PaperVNURLRouter
    @State private var selectedTab: PaperVNRootTab = .today
    @State private var rootSearchText = ""
    @State private var rootSearchScope: 搜索范围 = .visualNovel
    @State private var urlNavigationPath: [PaperVNURLRoute] = []
    @AppStorage(搜索设置偏好.独立搜索Tab设置键)
    private var isIndependentSearchTab = 搜索设置偏好.独立搜索Tab默认值

    var body: some View {
        rootContent
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .today:
                推荐后台分析中心.shared.设置Today分析暂停(true)
            default:
                推荐后台分析中心.shared.设置Today分析暂停(false)
            }
        }
        .onChange(of: urlRouter.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            selectedTab = .today
            urlNavigationPath = [request.route]
            urlRouter.consume(request)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if #available(iOS 18.0, *) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadRootContent
            } else {
                iosRootContent
            }
        } else {
            classicRootContent
        }
    }

    /// iOS 17 没有 `Tab` 与可自适应侧栏，iPhone 与 iPad 共用经典标签栏。
    private var classicRootContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $urlNavigationPath) {
                Today页面()
                    .navigationDestination(for: PaperVNURLRoute.self) { route in
                        PaperVNURLDestination(route, auth: auth)
                    }
            }
            .tabItem {
                Label("Today", systemImage: "doc.text.image")
                    .symbolVariant(.none)
            }
            .tag(PaperVNRootTab.today)

            资料库()
                .tabItem {
                    Label("资料库", systemImage: "square.stack.fill")
                }
                .tag(PaperVNRootTab.library(.all))

            NavigationStack {
                搜索(
                    searchText: $rootSearchText,
                    selectedScope: $rootSearchScope,
                    showsSearchField: true
                )
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
                    .accessibilityIdentifier(
                        PaperVNRootTabAccessibilityIdentifier.search
                    )
            }
            .tag(PaperVNRootTab.search)
        }
        .background {
            SearchTabContextMenuInstaller(
                onSelectScope: selectSearchScope(in:)
            )
            .frame(width: 0, height: 0)
        }
    }

    @available(iOS 18.0, *)
    private var iosRootContent: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .today) {
                NavigationStack(path: $urlNavigationPath) {
                    Today页面()
                        .navigationDestination(for: PaperVNURLRoute.self) { route in
                            PaperVNURLDestination(route, auth: auth)
                        }
                }
            } label: {
                Label("Today", systemImage: "doc.text.image")
                    .symbolVariant(.none)
            }
            .tabPlacement(.automatic)

            Tab(
                "资料库",
                systemImage: "square.stack.fill",
                value: .library(.all)
            ) {
                资料库()
            }
            .tabPlacement(.automatic)

            Tab(
                "搜索",
                systemImage: "magnifyingglass",
                value: .search,
                role: paperVNRootSearchTabRole(
                    isIndependent: isIndependentSearchTab
                )
            ) {
                NavigationStack {
                    搜索(
                        searchText: $rootSearchText,
                        selectedScope: $rootSearchScope,
                        showsSearchField: true
                    )
                }
            }
            .accessibilityIdentifier(
                PaperVNRootTabAccessibilityIdentifier.search
            )
        }
        .平台标签栏搜索自动激活()
        .background {
            SearchTabContextMenuInstaller(
                onSelectScope: selectSearchScope(in:)
            )
            .frame(width: 0, height: 0)
        }
        .平台根标签栏样式()
    }

    @available(iOS 18.0, *)
    private var iPadRootContent: some View {
        iPadPaperVNRoot(
            selection: $selectedTab,
            searchText: $rootSearchText,
            searchScope: $rootSearchScope,
            urlNavigationPath: $urlNavigationPath,
            isIndependentSearchTab: $isIndependentSearchTab
        )
    }

    private func selectSearchScope(in scope: 搜索范围) {
        rootSearchScope = scope
        selectedTab = .search
    }

}

@available(iOS 18.0, *)
private struct iPadPaperVNRoot: View {
    @Binding var selection: PaperVNRootTab
    @Binding var searchText: String
    @Binding var searchScope: 搜索范围
    @Binding var urlNavigationPath: [PaperVNURLRoute]
    @Binding var isIndependentSearchTab: Bool
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var kunAccount: 鲲Galgame账户
    @State private var isAccountPresented = false
    @State private var isSidebarVisible = true

    var body: some View {
        TabView(selection: $selection) {
            Tab(
                "搜索",
                systemImage: "magnifyingglass",
                value: .search,
                role: paperVNRootSearchTabRole(
                    isIndependent: isIndependentSearchTab,
                    isPad: true
                )
            ) {
                NavigationStack {
                    搜索(
                        searchText: $searchText,
                        selectedScope: $searchScope,
                        showsSearchField: true,
                        showsIPadToolbarScopePicker: true
                    )
                }
            }
            .customizationBehavior(.disabled, for: .sidebar)
            .tabPlacement(.automatic)

            Tab(value: .today) {
                NavigationStack(path: $urlNavigationPath) {
                    Today页面()
                        .navigationDestination(for: PaperVNURLRoute.self) { route in
                            PaperVNURLDestination(route, auth: auth)
                        }
                }
            } label: {
                Label("Today", systemImage: "doc.text.image")
                    .symbolVariant(.none)
            }
            .customizationBehavior(.disabled, for: .sidebar)

            TabSection {
                libraryTab(.all)
                libraryTab(.playing)
                libraryTab(.finished)
                libraryTab(.stalled)
                libraryTab(.dropped)
                libraryTab(.planning)
            } header: {
                Label("资料库", systemImage: "square.stack")
            }
        }
        .平台标签栏搜索自动激活()
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .background {
            iPadTabSidebarConfigurator(
                isSidebarVisible: $isSidebarVisible
            )
            .frame(width: 0, height: 0)
        }
        .tabViewSidebarBottomBar {
            accountButton
        }
        .sheet(isPresented: $isAccountPresented) {
            用户页面(
                auth: auth,
                isPresented: $isAccountPresented
            )
            .平台近全屏弹窗(dragIndicator: .hidden)
        }
    }

    private var accountButton: some View {
        Button {
            isAccountPresented = true
        } label: {
            Label {
                Text(verbatim: accountTitle)
                    .lineLimit(1)
            } icon: {
                鲲账户头像(
                    profile: kunAccount.isLoggedIn
                        ? kunAccount.profile
                        : nil,
                    size: 20
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 44,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel("用户与设置")
    }

    private var accountTitle: String {
        if kunAccount.isLoggedIn, let profile = kunAccount.profile {
            return profile.displayName
        }
        if auth.isLoggedIn {
            let username = auth.username.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !username.isEmpty {
                return username
            }
        }
        return String(localized: "登录")
    }

    private func libraryTab(_ filter: 用户列表筛选) -> some TabContent<PaperVNRootTab> {
        Tab(
            filter.localizedTitle,
            systemImage: sidebarSystemImage(for: filter),
            value: PaperVNRootTab.library(filter)
        ) {
            资料库(sidebarFilter: filter)
        }
        .customizationBehavior(.disabled, for: .sidebar)
    }

    private func sidebarSystemImage(for filter: 用户列表筛选) -> String {
        switch filter {
        case .playing: "play"
        case .dropped: "play.slash"
        default: filter.symbolName
        }
    }
}

@available(iOS 18.0, *)
private struct iPadTabSidebarConfigurator: UIViewControllerRepresentable {
    @Binding var isSidebarVisible: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = iPadTabSidebarConfiguratorController()
        let visibility = $isSidebarVisible
        controller.onSidebarVisibilityChange = { isVisible in
            visibility.wrappedValue = isVisible
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        guard let controller = uiViewController
            as? iPadTabSidebarConfiguratorController else {
            return
        }
        let visibility = $isSidebarVisible
        controller.onSidebarVisibilityChange = { isVisible in
            visibility.wrappedValue = isVisible
        }
    }
}

@available(iOS 18.0, *)
private final class iPadTabSidebarConfiguratorController: UIViewController {
    var onSidebarVisibilityChange: ((Bool) -> Void)?

    private weak var observedTabBarController: UITabBarController?
    private var sidebarVisibilityObservation: NSKeyValueObservation?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureTabBarController()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        configureTabBarController()
    }

    private func configureTabBarController() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let root = self.view.window?.rootViewController,
                  let tabBarController = Self.findTabBarController(in: root)
            else { return }

            tabBarController.mode = .tabSidebar
            tabBarController.customizationIdentifier = "PaperVN.iPadRoot"
            tabBarController.sidebar.preferredLayout = .overlap
            tabBarController.sidebar.isHidden = false

            guard self.observedTabBarController !== tabBarController else {
                self.onSidebarVisibilityChange?(
                    !tabBarController.sidebar.isHidden
                )
                return
            }

            self.observedTabBarController = tabBarController
            self.sidebarVisibilityObservation = tabBarController.sidebar.observe(
                \.isHidden,
                options: [.initial, .new]
            ) { [weak self] sidebar, _ in
                DispatchQueue.main.async {
                    self?.onSidebarVisibilityChange?(!sidebar.isHidden)
                }
            }
        }
    }

    private static func findTabBarController(
        in viewController: UIViewController
    ) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }

        for child in viewController.children {
            if let result = findTabBarController(in: child) {
                return result
            }
        }

        if let presented = viewController.presentedViewController {
            return findTabBarController(in: presented)
        }

        return nil
    }
}

private struct SearchTabContextMenuInstaller:
    UIViewControllerRepresentable {
    let onSelectScope: (搜索范围) -> Void

    func makeUIViewController(
        context: Context
    ) -> SearchTabContextMenuController {
        let controller = SearchTabContextMenuController()
        controller.onSelectScope = onSelectScope
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SearchTabContextMenuController,
        context: Context
    ) {
        uiViewController.onSelectScope = onSelectScope
        uiViewController.installWhenAvailable()
    }

    static func dismantleUIViewController(
        _ uiViewController: SearchTabContextMenuController,
        coordinator: Void
    ) {
        uiViewController.uninstall()
    }
}

private final class SearchTabContextMenuController:
    UIViewController,
    UIContextMenuInteractionDelegate {
    var onSelectScope: ((搜索范围) -> Void)?

    private weak var installedTargetView: UIView?
    private weak var interactionHostView: UIView?
    private var contextMenuInteraction: UIContextMenuInteraction?
    private var installationGeneration = 0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installWhenAvailable()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        installWhenAvailable()
    }

    func installWhenAvailable() {
        installationGeneration += 1
        attemptInstallation(
            generation: installationGeneration,
            remainingAttempts: 12
        )
    }

    func uninstall() {
        installationGeneration += 1
        removeInstalledInteraction()
    }

    private func removeInstalledInteraction() {
        if let contextMenuInteraction {
            interactionHostView?.removeInteraction(contextMenuInteraction)
        }
        contextMenuInteraction = nil
        interactionHostView = nil
        installedTargetView = nil
    }

    private func attemptInstallation(
        generation: Int,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (remainingAttempts == 12 ? 0 : 0.1)
        ) { [weak self] in
            guard let self,
                  generation == self.installationGeneration else {
                return
            }
            guard let tabBarController = self.tabBarController
                    ?? Self.findTabBarController(
                        in: self.view.window?.rootViewController
                    ),
                  let targetView = Self.searchTabControl(
                        in: tabBarController
                  ) else {
                if remainingAttempts > 1 {
                    self.attemptInstallation(
                        generation: generation,
                        remainingAttempts: remainingAttempts - 1
                    )
                }
                return
            }

            guard self.installedTargetView !== targetView
                    || self.interactionHostView !== targetView else {
                return
            }
            self.removeInstalledInteraction()

            let interaction = UIContextMenuInteraction(delegate: self)
            targetView.addInteraction(interaction)
            self.contextMenuInteraction = interaction
            self.interactionHostView = targetView
            self.installedTargetView = targetView
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let hostView = interaction.view,
              let targetView = installedTargetView,
              Self.isPoint(location, inside: targetView, in: hostView) else {
            return nil
        }
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil
        ) { [weak self] _ in
            guard let self else { return nil }
            let actions = 搜索范围.allCases.map { scope in
                UIAction(
                    title: scope.localizedTitle,
                    image: UIImage(systemName: scope.systemImage)
                ) { [weak self] _ in
                    self?.onSelectScope?(scope)
                }
            }
            return UIMenu(children: actions)
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration:
            UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            return nil
        }
        return transparentPreview(for: interaction)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration:
            UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            return nil
        }
        return transparentPreview(for: interaction)
    }

    private func transparentPreview(
        for interaction: UIContextMenuInteraction
    ) -> UITargetedPreview? {
        guard let sourceView = interaction.view else { return nil }
        let previewView = UIView(frame: .zero)
        previewView.backgroundColor = .clear
        previewView.isOpaque = false
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath()
        parameters.shadowPath = UIBezierPath()
        let target = UIPreviewTarget(
            container: sourceView,
            center: CGPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
        )
        return UITargetedPreview(
            view: previewView,
            parameters: parameters,
            target: target
        )
    }

    private static func searchTabControl(
        in tabBarController: UITabBarController
    ) -> UIView? {
        let rootView = tabBarController.view!
        let tabBar = tabBarController.tabBar

        if let identifiedView = firstDescendant(
            in: rootView,
            matching: {
                $0.accessibilityIdentifier
                    == PaperVNRootTabAccessibilityIdentifier.search
            }
        ), let control = enclosingControl(
            for: identifiedView,
            stoppingAt: rootView
        ) {
            return control
        }

        let controls = allDescendants(in: rootView).compactMap {
            $0 as? UIControl
        }.filter(isUsableTabControl(_:))
        let searchLabels = [
            tabBar.items?.last?.accessibilityLabel,
            tabBar.items?.last?.title,
            String(localized: "搜索")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let labeledControl = controls.first(where: { control in
            guard isNearTabBar(
                control,
                tabBar: tabBar,
                rootView: rootView
            ), let label = control.accessibilityLabel else {
                return false
            }
            return searchLabels.contains { searchLabel in
                label == searchLabel || label.hasPrefix(searchLabel)
            }
        }) {
            return labeledControl
        }

        let tabButtons = allDescendants(in: tabBar)
            .compactMap { $0 as? UIControl }
            .filter(isUsableTabControl(_:))
        guard tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        else {
            return tabButtons.max {
                $0.convert($0.bounds, to: tabBar).midX
                    < $1.convert($1.bounds, to: tabBar).midX
            }
        }
        return tabButtons.min {
            $0.convert($0.bounds, to: tabBar).midX
                < $1.convert($1.bounds, to: tabBar).midX
        }
    }

    private static func isPoint(
        _ point: CGPoint,
        inside targetView: UIView,
        in hostView: UIView
    ) -> Bool {
        hostView.convert(targetView.bounds, from: targetView).contains(point)
    }

    private static func enclosingControl(
        for view: UIView,
        stoppingAt rootView: UIView
    ) -> UIControl? {
        var candidate: UIView? = view
        while let current = candidate, current !== rootView {
            if let control = current as? UIControl {
                return control
            }
            candidate = current.superview
        }
        return nil
    }

    private static func isUsableTabControl(_ control: UIControl) -> Bool {
        !control.isHidden
            && control.alpha > 0
            && control.isUserInteractionEnabled
            && control.bounds.width >= 32
            && control.bounds.height >= 32
            && control.bounds.width <= 180
            && control.bounds.height <= 120
    }

    private static func isNearTabBar(
        _ view: UIView,
        tabBar: UITabBar,
        rootView: UIView
    ) -> Bool {
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: rootView)
            .insetBy(dx: -180, dy: -80)
        let viewFrame = view.convert(view.bounds, to: rootView)
        return tabBarFrame.intersects(viewFrame)
    }

    private static func firstDescendant(
        in view: UIView,
        matching predicate: (UIView) -> Bool
    ) -> UIView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let match = firstDescendant(
                in: subview,
                matching: predicate
            ) {
                return match
            }
        }
        return nil
    }

    private static func allDescendants(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allDescendants(in:))
    }

    private static func findTabBarController(
        in viewController: UIViewController?
    ) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let match = findTabBarController(in: child) {
                return match
            }
        }
        return nil
    }
}

private struct TabBarPreviewHost: View {
    var body: some View {
        TabBar()
            .environmentObject(PaperVNPremiumStore(previewing: true))
            .environmentObject(用户登录(previewing: true))
            .environmentObject(鲲Galgame账户(previewing: true))
            .environmentObject(Bangumi账户(previewing: true))
            .environmentObject(家长控制中心.shared)
            .environmentObject(PaperVNURLRouter())
    }
}

#Preview {
    TabBarPreviewHost()
}
