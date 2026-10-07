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
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadRootContent
        } else {
            iosRootContent
        }
    }

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
                        showsSearchField: true
                    )
                }
            }
            .accessibilityIdentifier(
                PaperVNRootTabAccessibilityIdentifier.search
            )
        }
        .平台标签栏搜索自动激活()
        .平台根标签栏样式()
    }

    private var iPadRootContent: some View {
        iPadPaperVNRoot(
            selection: $selectedTab,
            searchText: $rootSearchText,
            urlNavigationPath: $urlNavigationPath,
            isIndependentSearchTab: $isIndependentSearchTab
        )
    }


}

private struct iPadPaperVNRoot: View {
    @Binding var selection: PaperVNRootTab
    @Binding var searchText: String
    @Binding var urlNavigationPath: [PaperVNURLRoute]
    @Binding var isIndependentSearchTab: Bool
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var kunAccount: 鲲Galgame账户
    @State private var isAccountPresented = false

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
                        showsSearchField: true
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
