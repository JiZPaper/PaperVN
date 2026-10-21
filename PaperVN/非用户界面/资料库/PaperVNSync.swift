import Combine
import Foundation

/// PaperVN Sync：资料库适配服务。
///
/// 本地资料库是事实来源，PaperVN Sync为每个作品找到它在各平台的ID，再通过各平台的API同步资料库。
/// 视觉小说从VNDB导入，并推送到Bangumi；动画、漫画与轻小说在MyAnimeList、AniList与Annict之间双向同步，
/// 合并规则见 `同步合并`。
@MainActor
final class PaperVNSync中心: ObservableObject {
    static let shared = PaperVNSync中心()

    enum 任务状态: Equatable {
        case 等待
        case 进行中(已完成: Int, 总数: Int?)
        case 完成(Date)
        case 失败(String)
        /// 有冲突或需要确认的情况，等待用户处理。
        case 需要处理
    }

    struct 同步任务: Identifiable, Equatable {
        let 平台: 资料库平台
        let 标题: String
        var 状态: 任务状态

        var id: 资料库平台 { 平台 }
    }

    @Published private(set) var 任务: [资料库平台: 同步任务] = [:]
    /// 各平台最近一次同步完成的时间，保存在本机。
    @Published private(set) var 最近同步时间: [资料库平台: Date] = 读取最近同步时间()

    /// 等待用户处理的同步。用户关闭处理页面后仍然保留，可以在同步任务页面继续处理。
    @Published private(set) var 待处理: 同步会话?
    @Published var 显示待处理 = false
    /// 这次同步中前几步停下时的会话，按顺序保存，用来返回上一步重新选择。
    @Published private(set) var 上一步: [同步会话] = []
    /// 能弹出处理页面的位置（App 根视图、“账户与设置”），后出现的在上层。
    /// 已经有弹出页面时，从根视图再弹出会被系统静默忽略，所以处理页面由最上层的位置弹出。
    @Published private(set) var 弹出层级: [UUID] = []



    func 注册弹出层级(_ id: UUID) {
        if !弹出层级.contains(id) { 弹出层级.append(id) }
    }

    func 注销弹出层级(_ id: UUID) {
        弹出层级.removeAll { $0 == id }
    }
    /// 各平台找不到对应作品、没有同步过去的作品，可以手动匹配。
    @Published private(set) var 未匹配作品: [资料库平台: [未匹配作品]] = [:]
    var 未匹配数: [资料库平台: Int] { 未匹配作品.mapValues(\.count) }
    /// 最近一次同步时读取失败的平台与原因。
    @Published private(set) var 读取失败: [资料库平台: String] = [:]
    /// 分别保留时在资料库中隐藏的作品数。
    @Published private(set) var 隐藏数 = 0
    /// 用户在资料库顶部忽略过的缺失作品（“平台|编号”）。发现新的缺失作品时再次提示。
    @Published private(set) var 已忽略缺失: Set<String> = Set(UserDefaults.standard.stringArray(forKey: 已忽略缺失键) ?? [])
    private static let 已忽略缺失键 = "paperVNSyncDismissedUnmatched"

    private var 缺失作品标识: Set<String> {
        Set(未匹配作品.flatMap { platform, works in works.map { "\(platform.rawValue)|\($0.键)" } })
    }

    /// 有用户还没忽略过的缺失作品。
    var 有新的缺失作品: Bool { !缺失作品标识.isSubset(of: 已忽略缺失) }

    /// 忽略当前的缺失作品，直到发现更多或其他缺失的作品。
    func 忽略缺失作品() {
        已忽略缺失 = 缺失作品标识
        UserDefaults.standard.set(Array(已忽略缺失), forKey: Self.已忽略缺失键)
    }

    nonisolated static let 启用设置键 = "paperVNSyncEnabled"
    private static let 最近同步时间键 = "paperVNSyncLastSynchronized"

    /// 资料库的内容都来自PaperVN Sync，所以默认开启；关闭后资料库不可用。
    nonisolated static let 默认启用 = true

    /// PaperVN Sync开启后，已登录的平台都会同步；没有单独的平台开关。
    nonisolated static var 已启用: Bool {
        _ = 旧开关已迁移
        return UserDefaults.standard.object(forKey: 启用设置键) as? Bool ?? 默认启用
    }

    nonisolated private static let 旧开关已迁移: Void = 迁移旧开关()

    static func 记录同步完成(_ platform: 资料库平台, at date: Date = .now) {
        shared.最近同步时间[platform] = date
        let values = Dictionary(
            uniqueKeysWithValues: shared.最近同步时间.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }
        )
        UserDefaults.standard.set(values, forKey: 最近同步时间键)
    }

    private static func 读取最近同步时间() -> [资料库平台: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: 最近同步时间键) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            资料库平台(rawValue: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }

    /// 旧版本Bangumi有单独的“资料库同步”开关，现在统一由PaperVN Sync控制。
    nonisolated private static func 迁移旧开关() {
        let legacyKey = "bangumiCollectionSyncEnabled"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyKey) != nil else { return }
        // 默认已经开启，旧开关只需要清理
        defaults.removeObject(forKey: legacyKey)
    }

    var 正在同步: Bool {
        任务.values.contains {
            if case .进行中 = $0.状态 { return true }
            return false
        }
    }

    /// 由App在启动时设置。
    weak var myAnimeList: MyAnimeList账户?
    weak var aniList: AniList账户?
    weak var annict: Annict账户?
    weak var tmdb: TMDB账户?
    weak var bangumi: Bangumi账户?

    func 连接账户(myAnimeList: MyAnimeList账户, aniList: AniList账户, annict: Annict账户, tmdb: TMDB账户, bangumi: Bangumi账户) {
        if self.myAnimeList !== myAnimeList { self.myAnimeList = myAnimeList }
        if self.aniList !== aniList { self.aniList = aniList }
        if self.annict !== annict { self.annict = annict }
        if self.tmdb !== tmdb { self.tmdb = tmdb }
        if self.bangumi !== bangumi { self.bangumi = bangumi }
    }
    private var 动画同步: Task<Void, Never>?

    private var vndb导入: Task<Void, Never>?
    private var vndb导入标识: UUID?
    private var 资料库变化监听: AnyCancellable?

    private init() {
        // 编辑页与详情页直接写入VNDB后会发出这个通知，此时重新导入
        资料库变化监听 = NotificationCenter.default
            .publisher(for: .paperVNLibraryDidChange)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.重新导入VNDB() }
            }
    }

    private var 上次凭据: (token: String, userID: String)?

    // MARK: 视觉小说

    /// 从VNDB导入视觉小说。`forceRefresh` 为假时允许使用VNDB服务的短期缓存。
    func 从VNDB导入(token: String, userID: String, forceRefresh: Bool) async {
        guard Self.已启用, !token.isEmpty, !userID.isEmpty else { return }
        上次凭据 = (token, userID)
        本地资料库.shared.切换所有者(userID)

        let 标识 = UUID()
        vndb导入标识 = 标识
        vndb导入?.cancel()
        任务[.vndb] = 同步任务(
            平台: .vndb,
            标题: String(localized: "从VNDB导入视觉小说"),
            状态: .进行中(已完成: 0, 总数: nil)
        )
        let task = Task {
            // 先等资料库从磁盘读完，否则导入会把还没读出来的动画、漫画与轻小说覆盖掉
            await 本地资料库.shared.等待载入()
            do {
                let items = try await VNDB服务.shared.fetchAllUserList(
                    token: token,
                    userID: userID,
                    forceRefresh: forceRefresh
                )
                guard vndb导入标识 == 标识 else { return }
                本地资料库.shared.导入VNDB(items, owner: userID)
                任务[.vndb]?.状态 = .完成(.now)
                Self.记录同步完成(.vndb)
            } catch is CancellationError {
                return
            } catch {
                guard vndb导入标识 == 标识 else { return }
                任务[.vndb]?.状态 = .失败(Self.错误说明(error))
            }
        }
        vndb导入 = task
        await task.value
    }

    private func 重新导入VNDB() {
        guard let 上次凭据 else { return }
        Task {
            await 从VNDB导入(
                token: 上次凭据.token,
                userID: 上次凭据.userID,
                forceRefresh: true
            )
        }
    }

    // MARK: 动画、漫画与轻小说

    /// 已登录、参与动画同步的平台。
    private var 已登录平台: [资料库平台] {
        资料库平台.动画漫画平台.filter { platform in
            switch platform {
            case .myAnimeList: myAnimeList?.isLoggedIn == true
            case .aniList: aniList?.isLoggedIn == true
            case .annict: annict?.isLoggedIn == true
            case .tmdb: tmdb?.isLoggedIn == true
            case .bangumi: bangumi?.isLoggedIn == true
            default: false
            }
        }
    }

    struct 资料库编辑限制: Equatable {
        /// 已登录、但无法同步这类作品的平台：Bangumi 只导入，Annict 只有动画，VNDB 只有视觉小说。
        let 无法同步: [资料库平台]
        /// 登录其中之一就能编辑。
        let 可登录: [资料库平台]
    }

    /// 已登录的平台都无法同步这类作品时（只登录了 VNDB 或 Bangumi，或编辑漫画、轻小说时只登录了 Annict）不能编辑，
    /// 否则修改只留在本机、平台上的记录又会在同步时盖回来。可以编辑时返回 nil。
    func 需要登录才能编辑(_ type: 作品类型) -> 资料库编辑限制? {
        // 资料库的所有者是 VNDB 账户；没有登录其他平台时，就是只登录了 VNDB
        var platforms = 已登录平台
        if platforms.isEmpty, 本地资料库.shared.所有者 != nil { platforms = [.vndb] }
        guard !platforms.isEmpty,
              !platforms.contains(where: { $0.同步能力.支持写入 && $0.同步能力.支持的类型.contains(type) }) else { return nil }
        return 资料库编辑限制(
            无法同步: platforms,
            可登录: 资料库平台.动画漫画平台.filter { $0.同步能力.支持写入 && $0.同步能力.支持的类型.contains(type) }
        )
    }

    /// 参与同步的平台：已登录、同步方式不是“无”的。
    private var 同步平台: [资料库平台] { 已登录平台.filter { $0.同步方向 != .无 } }

    private func 账户信息(_ platform: 资料库平台) -> (id: String, name: String)? {
        switch platform {
        case .myAnimeList: myAnimeList?.profile.map { (String($0.id), $0.name) }
        case .aniList: aniList?.profile.map { (String($0.id), $0.name) }
        case .annict: annict?.profile.map { (String($0.annictId), $0.username) }
        case .tmdb: tmdb?.profile.map { (String($0.id), $0.username) }
        case .bangumi: bangumi?.profile.map { (String($0.id), $0.displayName) }
        default: nil
        }
    }

    /// 读取所有已登录平台的资料库并合并。遇到需要用户决定的情况时停下，等用户在处理页面里选择。
    func 同步动画漫画() async {
        guard Self.已启用, let owner = 本地资料库.shared.所有者 else { return }
        // 上一次的冲突还没处理完时不重新开始，避免用户的选择被覆盖
        guard 待处理 == nil, 动画同步 == nil else {
            await 动画同步?.value
            return
        }
        let platforms = 同步平台
        guard !platforms.isEmpty else { return }
        // 资料库从磁盘读完、读取成功之后才同步；否则会把还没读出来的资料库当成空的
        await 本地资料库.shared.等待载入()
        guard 本地资料库.shared.可写入, 本地资料库.shared.所有者 == owner else { return }

        let task = Task {
            // 无论在哪一步结束（读取失败、账户信息缺失、取消），都不能让平台一直显示“正在同步”
            defer {
                for platform in platforms {
                    if case .进行中 = 任务[platform]?.状态 { 任务[platform]?.状态 = .等待 }
                }
            }
            for platform in platforms {
                任务[platform] = 同步任务(
                    平台: platform,
                    标题: String(localized: "同步\(platform.localizedTitle)"),
                    状态: .进行中(已完成: 0, 总数: nil)
                )
            }
            var libraries: [资料库平台: 平台资料库] = [:]
            var failures: [资料库平台: String] = [:]
            // 校准表、预装的作品映射和各平台的资料库同时读取
            async let calibrations: Void = 作品匹配校准.shared.更新()
            async let workMap: Void = 作品映射.预载()
            async let mal = 读取结果(.myAnimeList, in: platforms)
            async let ani = 读取结果(.aniList, in: platforms)
            async let ann = 读取结果(.annict, in: platforms)
            async let bgm = 读取结果(.bangumi, in: platforms)
            async let tmd = 读取结果(.tmdb, in: platforms)
            // 新增平台时这里也要加上，否则该平台会被跳过，既不报错也不同步（曾经漏掉过 Bangumi）
            let results = await [mal, ani, ann, bgm, tmd].compactMap { $0 }
            await calibrations
            await workMap
            assert(Set(results.map(\.0)) == Set(platforms), "有已登录的平台没有被读取")
            for (platform, result) in results {
                switch result {
                case let .success(records):
                    guard let account = 账户信息(platform) else {
                        let message = String(localized: "无法读取账户信息，请重新登录。")
                        failures[platform] = message
                        任务[platform]?.状态 = .失败(message)
                        continue
                    }
                    libraries[platform] = 平台资料库(
                        平台: platform,
                        账户ID: account.id,
                        账户名称: account.name,
                        记录: records
                    )
                case let .failure(error):
                    // 读取失败的平台不参与这次同步，不能当成“资料库是空的”
                    let message = Self.错误说明(error)
                    failures[platform] = message
                    任务[platform]?.状态 = .失败(message)
                }
            }
            读取失败 = failures
            guard !Task.isCancelled, !libraries.isEmpty, 本地资料库.shared.所有者 == owner else { return }

            var store = 同步状态存储.读取(owner: owner)
            var local = 本地资料库.shared.动画漫画条目
            未匹配作品 = store.未匹配作品
            // 各平台的条目按对应关系归到作品：手动匹配与校准表 → 预装的作品映射 → 以前在 MAL 上找到的对应。
            // 同步时不按标题现场匹配；对不上的作品可以在同步任务里手动匹配
            for platform in Array(libraries.keys) {
                guard var platformLibrary = libraries[platform] else { continue }
                var records: [平台资料库记录] = []
                for var record in Array(platformLibrary.记录.values) + platformLibrary.附属记录 {
                    Self.对应作品(&record, store: store)
                    records.append(record)
                }
                (platformLibrary.记录, platformLibrary.附属记录) = 同步合并.每部作品一条(records)
                libraries[platform] = platformLibrary
            }
            // 一次性清理：之前的版本会把“覆盖”后 Bangumi 删不掉的作品从 Bangumi 恢复回资料库。
            // 只在不能删除的平台（Bangumi）上有、也没有等着推送的作品，从资料库移除并记为已删除
            if !store.已清理误恢复的作品 {
                for (key, _) in local where !key.hasPrefix("mal-") && store.待推送[key] == nil {
                    let holders = libraries.values.filter { $0.记录[key] != nil }.map(\.平台)
                    guard !holders.isEmpty, holders.allSatisfy({ !$0.同步能力.支持删除 }) else { continue }
                    local[key] = nil
                    store.本地已删除.insert(key)
                }
                store.已清理误恢复的作品 = true
            }
            // 刚对上 MAL ID 的作品以前是按平台 ID 编号的（例如“bangumi-anime:537409”），
            // 资料库、基线、待推送里的旧编号都改成新编号，否则会被当成平台上删除了一部作品
            Self.核对已有对应(&libraries, local: &local, store: &store)
            // 附属条目以前单独成为一部作品，也改成它所属作品的编号（资料库里已经有那部作品时，旧的记录直接去掉）。
            // 旧编号不只“平台-类型:ID”一种：以前的对应表、旧版本的映射可能给过别的编号，所以按资料库条目自己记着的平台 ID 找
            var newKeyOfPlatformID: [String: String] = [:]
            for (platform, platformLibrary) in libraries {
                for record in Array(platformLibrary.记录.values) + platformLibrary.附属记录 {
                    newKeyOfPlatformID["\(platform.rawValue)|\(record.平台ID)"] = record.键
                }
            }
            var renames: [(old: String, new: String)] = []
            for entry in local.values {
                let targets = Set(entry.平台ID.compactMap { newKeyOfPlatformID["\($0.key.rawValue)|\($0.value)"] })
                if targets.count == 1, let target = targets.first, target != entry.id {
                    renames.append((entry.id, target))
                }
            }
            for (platform, platformLibrary) in libraries {
                for record in Array(platformLibrary.记录.values) + platformLibrary.附属记录 {
                    renames.append((同步合并.键(类型: record.类型, malID: nil, 平台: platform, 平台ID: record.平台ID), record.键))
                }
            }
            do {
                for (oldKey, newKey) in renames {
                    guard oldKey != newKey else { continue }
                    if var entry = local.removeValue(forKey: oldKey) {
                        if local[newKey] == nil {
                            entry.id = newKey
                            local[newKey] = entry
                        }
                    }
                    for basePlatform in Array(store.基线.keys) {
                        if let value = store.基线[basePlatform]?.快照.removeValue(forKey: oldKey),
                           store.基线[basePlatform]?.快照[newKey] == nil {
                            store.基线[basePlatform]?.快照[newKey] = value
                        }
                    }
                    if let pendingPlatforms = store.待推送.removeValue(forKey: oldKey) {
                        store.待推送[newKey, default: []].formUnion(pendingPlatforms)
                    }
                }
            }
            // AniList 在 PaperVN 新建记录时自动填上的日期：资料库和这次读到的记录都改回应有的日期，推送时再改 AniList
            var aniListDateFixes: [String: 同步日期] = [:]
            for (key, record) in libraries[.aniList]?.记录 ?? [:] {
                guard let entry = local[key],
                      let fix = 同步合并.AniList自动填写的日期(
                          record,
                          本地: entry,
                          基线: store.基线[.aniList]?.快照[key],
                          其他记录: libraries.values.filter { $0.平台 != .aniList }.compactMap { $0.记录[key] }
                      ) else { continue }
                aniListDateFixes[key] = fix
                local[key]?.开始日期 = fix.开始
                local[key]?.完成日期 = fix.完成
                libraries[.aniList]?.记录[key]?.开始日期 = fix.开始
                libraries[.aniList]?.记录[key]?.完成日期 = fix.完成
            }
            // 隐藏的作品后来又在 PaperVN 中加入资料库时，不再隐藏
            for key in store.隐藏.keys where local[key] != nil {
                store.隐藏[key] = nil
                store.隐藏条目[key] = nil
            }
            store.保存(owner: owner)
            隐藏数 = store.隐藏条目.count
            // 隐藏的作品不参与同步
            var bases = store.基线
            for key in store.隐藏.keys {
                for platform in libraries.keys {
                    libraries[platform]?.记录[key] = nil
                    bases[platform]?.快照[key] = nil
                }
            }
            var session = 同步会话(
                本地: local,
                平台: libraries,
                基线: bases,
                待推送: store.待推送.filter { store.隐藏[$0.key] == nil }
            )
            session.本地已删除 = store.本地已删除
            session.AniList日期修正 = aniListDateFixes
            session.仅导出 = Set(platforms.filter { $0.同步方向 == .仅导出 })
            session.仅导入 = Set(platforms.filter { !$0.可导出 })
            session.读取失败 = failures
            let loggedIn = Set(已登录平台)
            for platform in 资料库平台.动画漫画平台 where failures[platform] == nil {
                if !loggedIn.contains(platform) {
                    session.未参与[platform] = .未登录
                } else if platform.同步方向 == .无 {
                    session.未参与[platform] = .同步方式为无
                } else if platform.同步方向 == .仅导出 {
                    session.未参与[platform] = .仅导出
                } else if libraries[platform]?.记录.isEmpty ?? true {
                    session.未参与[platform] = .资料库为空
                }
            }
            同步合并.检查减少(&session)
            上一步 = []
            await 继续(session)
        }
        动画同步 = task
        await task.value
        动画同步 = nil
    }

    private func 读取结果(
        _ platform: 资料库平台,
        in platforms: [资料库平台]
    ) async -> (资料库平台, Result<[平台资料库记录], Error>)? {
        guard platforms.contains(platform) else { return nil }
        do {
            return (platform, .success(try await 读取(platform)))
        } catch {
            return (platform, .failure(error))
        }
    }

    private func 读取(_ platform: 资料库平台) async throws -> [平台资料库记录] {
        switch platform {
        case .myAnimeList:
            guard let account = myAnimeList else { return [] }
            async let anime = account.animeList()
            async let manga = account.mangaList()
            return try await (anime + manga).compactMap(\.平台记录)
        case .aniList:
            return try await aniList?.读取资料库() ?? []
        case .annict:
            return try await annict?.读取资料库() ?? []
        case .tmdb:
            return try await tmdb?.读取资料库() ?? []
        case .bangumi:
            return try await bangumi?.读取动画漫画资料库() ?? []
        default:
            return []
        }
    }

    /// 按顺序推进：资料库减少 → 导入方式 → 逐项冲突 → 确认推送 → 推送。缺用户的选择就停下。
    private func 继续(_ session: 同步会话) async {
        var session = session

        if session.减少提示.contains(where: { session.减少处理[$0.平台] == nil }) {
            等待用户(session)
            return
        }
        if !session.已应用减少处理 {
            同步合并.忽略保留平台的删除(&session)
            session.已应用减少处理 = true
        }
        if !session.已检查导入方式 {
            同步合并.检查导入方式(&session)
            session.已检查导入方式 = true
        }
        if session.需要选择导入方式, session.导入方式 == nil {
            等待用户(session)
            return
        }
        if !session.冲突已生成 {
            同步合并.合并(&session)
        }
        if session.冲突.contains(where: { $0.选择 == nil }) {
            等待用户(session)
            return
        }
        同步合并.应用冲突选择(&session)
        同步合并.生成推送(&session)
        填入已查到的ID(&session)

        // 先让用户确认，再去平台上查找要添加的作品：查找可能要逐部搜索，作品多时要很久，不能让确认等着它
        if session.需要确认推送, !session.已确认推送 {
            等待用户(session)
            return
        }
        await 查找平台ID(&session)
        await 执行(session)
    }

    /// 等用户处理。不自动弹出处理页面：资料库顶部会显示提示，用户点按后再打开。
    private func 等待用户(_ session: 同步会话) {
        // 从上一步继续到这里：记下上一步停下时的会话，返回时恢复，之前做的选择也还在
        if let previous = 待处理 { 上一步.append(previous) }
        待处理 = session
        for platform in session.平台.keys {
            任务[platform]?.状态 = .需要处理
        }
    }

    /// 用户做出选择后继续同步。记在“动画同步”里，期间新的同步会等它结束，不会同时进行两次。
    private func 开始继续(_ session: 同步会话) {
        let platforms = Array(session.平台.keys)
        let task = Task {
            await 继续(session)
            // 中途退出时不能让平台一直显示“正在同步”
            for platform in platforms {
                if case .进行中 = 任务[platform]?.状态 { 任务[platform]?.状态 = .等待 }
            }
        }
        动画同步 = task
        Task {
            await task.value
            if 动画同步 == task { 动画同步 = nil }
        }
    }

    /// 资料库顶部提示的说明文字。
    static func 待处理说明(_ session: 同步会话?) -> String? {
        guard let session else { return nil }
        if session.减少提示.contains(where: { session.减少处理[$0.平台] == nil }) {
            let names = session.减少提示.map(\.平台.localizedTitle).joined(separator: "、")
            return String(localized: "\(names)上的作品比上次同步时少了很多。")
        }
        if session.需要选择导入方式, session.导入方式 == nil {
            return String(localized: "资料库内容不同，需要选择导入方式。")
        }
        if session.冲突已生成, !session.冲突.isEmpty {
            return String(localized: "有\(session.冲突.count)项更改需要确认。")
        }
        return String(localized: "确认以同步动画、漫画与轻小说。")
    }

    // MARK: 用户的选择

    func 选择减少处理(_ choice: 减少处理, for platform: 资料库平台) {
        待处理?.减少处理[platform] = choice
    }

    /// 资料库减少的提示都选好后继续。
    func 确认减少处理() {
        guard let session = 待处理 else { return }
        开始继续(session)
    }

    func 选择导入方式(_ method: 导入方式) {
        guard var session = 待处理 else { return }
        session.导入方式 = method
        开始继续(session)
    }

    func 选择冲突版本(_ source: 同步来源, for key: String) {
        guard let index = 待处理?.冲突.firstIndex(where: { $0.键 == key }) else { return }
        待处理?.冲突[index].选择 = source
    }

    /// 所有冲突都使用同一个来源；该来源没有的冲突保持不变。
    func 全部选择(_ source: 同步来源) {
        guard var session = 待处理 else { return }
        for index in session.冲突.indices where session.冲突[index].版本.contains(where: { $0.来源 == source }) {
            session.冲突[index].选择 = source
        }
        待处理 = session
    }

    func 确认冲突() {
        guard let session = 待处理, !session.冲突.contains(where: { $0.选择 == nil }) else { return }
        开始继续(session)
    }

    func 选择修改时间来源(_ platform: 资料库平台) {
        待处理?.修改时间来源 = platform
    }

    /// 回到上一步停下的地方。
    func 返回上一步() {
        guard 动画同步 == nil, let previous = 上一步.popLast() else { return }
        待处理 = previous
    }

    func 确认推送() {
        guard var session = 待处理,
              !session.需要选择修改时间来源 || session.修改时间来源 != nil else { return }
        session.已确认推送 = true
        // 确认后立即关闭处理页面，进度显示在资料库顶部和同步任务页面
        待处理 = nil
        上一步 = []
        显示待处理 = false
        // 已经确认：查找作品期间各平台显示正在同步，不再显示“需要确认”
        for platform in session.平台.keys {
            任务[platform]?.状态 = .进行中(已完成: 0, 总数: nil)
        }
        开始继续(session)
    }

    /// 重新读取所有平台。还没处理完的选择会被放弃，因为读到的数据可能已经不同。
    func 重试() {
        取消待处理()
        Task { await 同步动画漫画() }
    }

    /// 把隐藏的作品加入资料库，并推送到其他已登录的平台。
    func 显示隐藏的作品() {
        guard let owner = 本地资料库.shared.所有者 else { return }
        var store = 同步状态存储.读取(owner: owner)
        guard !store.隐藏条目.isEmpty else { return }
        let platforms = Set(已登录平台)
        for entry in store.隐藏条目.values {
            本地资料库.shared.添加(entry)
            // 记为在 PaperVN 中做的修改：缺少这部作品的平台会自动加入
            store.待推送[entry.id, default: []].formUnion(platforms.filter { $0.可导出 && $0.同步能力.支持的类型.contains(entry.类型) })
        }
        store.隐藏 = [:]
        store.隐藏条目 = [:]
        store.保存(owner: owner)
        隐藏数 = 0
        Task { await 同步动画漫画() }
    }

    /// 用户手动选出作品在平台上对应的作品：记下对应关系并匿名提交到后台，然后重新同步。
    /// `附属` 为真时，这部作品是所选作品的特别篇、单行本或其他版本：它在其他平台上的条目并入所选作品，不单独同步。
    func 手动匹配(_ work: 未匹配作品, 平台 platform: 资料库平台, 作品 match: 匹配候选, 附属: Bool = false) {
        guard let owner = 本地资料库.shared.所有者 else { return }
        var store = 同步状态存储.读取(owner: owner)
        if 附属 {
            store.手动匹配.append(作品对应组(
                类型: work.类型,
                ids: [platform: match.id],
                附属: work.已知ID.filter { $0.key != platform }.mapValues { [$0] }
            ))
        } else {
            var ids = work.已知ID
            ids[platform] = match.id
            store.手动匹配.append(作品对应组(类型: work.类型, ids: ids))
        }
        store.未匹配作品[platform]?.removeAll { $0.键 == work.键 }
        if store.未匹配作品[platform]?.isEmpty == true { store.未匹配作品[platform] = nil }
        store.保存(owner: owner)
        未匹配作品 = store.未匹配作品
        Task {
            _ = await 作品匹配校准.shared.提交([作品匹配校准.提交项(work, 平台: platform, 手动匹配: match, 附属: 附属)])
        }
        Task { await 同步动画漫画() }
    }

    /// 在平台上搜索作品，手动匹配时使用。
    func 搜索候选(_ platform: 资料库平台, 类型 type: 作品类型, 关键词 query: String) async throws -> [匹配候选] {
        switch platform {
        case .myAnimeList:
            guard let myAnimeList else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            return try await myAnimeList.搜索候选(类型: type, 关键词: query)
        case .aniList:
            guard let aniList else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            return try await aniList.搜索候选(类型: type, 关键词: query)
        case .annict:
            guard let annict else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            return try await annict.搜索候选(关键词: query)
        case .bangumi:
            guard let bangumi else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            return try await bangumi.搜索候选(类型: type, 关键词: query)
        case .tmdb:
            guard let tmdb else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            return try await tmdb.搜索候选(关键词: query)
        case .vndb:
            return []
        }
    }

    /// 放弃这次同步，不修改资料库和任何平台。下次同步时会重新检查。
    func 取消待处理() {
        guard let session = 待处理 else { return }
        待处理 = nil
        上一步 = []
        显示待处理 = false
        for platform in session.平台.keys {
            任务[platform]?.状态 = .等待
        }
    }

    // MARK: 推送

    /// 新增作品时找出它在平台上的 ID：手动匹配与校准表、预装的作品映射、MAL ID。
    /// 不按标题现场搜索；找不到的记为未匹配、不推送，可以在同步任务里手动匹配。
    private func 查找平台ID(_ session: inout 同步会话) async {
        let missing = session.推送.filter { $0.种类 == .新增 && $0.平台ID == nil }
        var found = session.查找到的ID
        var unmatched: [资料库平台: [String]] = [:]
        let manual = 本地资料库.shared.所有者.map { 同步状态存储.读取(owner: $0).手动匹配 } ?? []
        for operation in missing where found[operation.平台]?[operation.键] == nil {
            let id = 作品匹配校准.shared.平台ID(operation.平台, 类型: operation.类型, 已知: Self.已知ID(operation, session: session), 手动: manual)
                ?? 作品映射.平台ID(operation.键, 平台: operation.平台, 类型: operation.类型)
                ?? (operation.平台 == .myAnimeList ? operation.malID.map(String.init) : nil)
            if let id { found[operation.平台, default: [:]][operation.键] = id }
        }
        // 映射文件之后才在 AniList 上出现的作品：按 MAL ID 精确查询（不是按标题搜索）
        if let account = aniList {
            for type in [作品类型.anime, .manga] {
                let group = missing.filter { $0.平台 == .aniList && found[.aniList]?[$0.键] == nil && ($0.类型 == .anime) == (type == .anime) }
                let ids = group.compactMap(\.malID)
                guard !ids.isEmpty, let result = try? await account.查找(malIDs: ids, 类型: type) else { continue }
                for operation in group {
                    if let malID = operation.malID, let id = result[malID] {
                        found[.aniList, default: [:]][operation.键] = String(id)
                    }
                }
            }
        }
        session.查找到的ID = found
        填入已查到的ID(&session)
        // 查到的作品其实已经在该平台的资料库里（标题对应前被当成了另一部）：不要重新写入，免得改掉平台上的记录和更改时间
        session.推送.removeAll { operation in
            guard operation.种类 == .新增, let id = operation.平台ID else { return false }
            return session.平台[operation.平台]?.记录.values.contains { $0.平台ID == id } == true
        }
        // TMDB 把一部剧的各季算作一个条目，只写入第一季对应的作品；之后各季在 TMDB 上没有单独的条目，不算找不到
        // Annict 把 MAL 的部分特别篇并在正篇的话里，这些作品在 Annict 上同样没有单独的条目
        session.推送.removeAll { operation in
            guard operation.种类 == .新增, operation.平台ID == nil else { return false }
            return (operation.平台 == .tmdb && 作品映射.TMDB季(operation.键) != nil)
                || (operation.平台 == .annict && 作品映射.Annict并入正篇(operation.键))
        }
        for operation in session.推送 where operation.种类 == .新增 && operation.平台ID == nil {
            unmatched[operation.平台, default: []].append(operation.键)
        }
        session.未匹配 = unmatched
    }

    /// 资料库里已经记着的对应关系（以前同步时对上的平台条目）和作品映射不一致时：
    /// - 映射只给出较弱的编号（没有 MAL ID，例如 AniList 上没有 MAL ID 的轻小说）：保留资料库里的对应；
    /// - 映射把这个平台条目对到了另一部有 MAL ID 的作品（以前对错了，例如把“虹ヶ咲 2期”对到了总集篇）：
    ///   这个平台条目不再属于这部作品，去掉对应和这个平台的基线，免得被当成“在平台上删除”。
    static func 核对已有对应(
        _ libraries: inout [资料库平台: 平台资料库],
        local: inout [String: 本地资料库条目],
        store: inout 同步状态存储
    ) {
        for (key, entry) in local where key.hasPrefix("mal-") {
            guard let colon = key.firstIndex(of: ":"), let malID = Int(key[key.index(after: colon)...]) else { continue }
            for (platform, platformID) in entry.平台ID where platform != .myAnimeList {
                guard var library = libraries[platform] else { continue }
                var records = Array(library.记录.values) + library.附属记录
                guard let index = records.firstIndex(where: { $0.平台ID == platformID }), records[index].键 != key else { continue }
                if records[index].键.hasPrefix("mal-") {
                    // 资料库里的记录是从这个对错的平台条目来的（和它的基线一样）：改回 MAL 上的记录，
                    // 否则会被当成在 PaperVN 中做的更改，写到 MAL 上（例如把“2期”的 13 集写到总集篇上）
                    if let wrong = store.基线[platform]?.快照[key], let current = local[key],
                       同步合并.快照(current) == wrong,
                       let mal = libraries[.myAnimeList]?.记录[key]?.快照, mal != wrong {
                        local[key]?.状态 = mal.状态
                        local[key]?.评分 = mal.评分
                        local[key]?.进度 = mal.进度
                    }
                    store.基线[platform]?.快照[key] = nil
                    local[key]?.平台ID[platform] = nil
                } else {
                    records[index].指定键 = key
                    records[index].附属 = nil
                    records[index].malID = malID
                    (library.记录, library.附属记录) = 同步合并.每部作品一条(records)
                    libraries[platform] = library
                }
            }
        }
    }

    /// 平台条目属于哪部作品。手动匹配与后台校准最优先（用来改正映射），其次是预装的作品映射。
    private static func 对应作品(_ record: inout 平台资料库记录, store: 同步状态存储) {
        let platform = record.平台
        if let mapped = 作品匹配校准.shared.查找(platform, 平台ID: record.平台ID, 类型: record.类型, 手动: store.手动匹配)
            ?? 作品映射.查找(platform, 平台ID: record.平台ID, 类型: record.类型) {
            record.指定键 = mapped.键
            record.附属 = mapped.附属 ? true : nil
            if let colon = mapped.键.firstIndex(of: ":"), mapped.键.hasPrefix("mal-"),
               let malID = Int(mapped.键[mapped.键.index(after: colon)...]) {
                record.malID = malID
            }
            return
        }
        if record.malID == nil, platform != .myAnimeList,
           let malID = store.已知MALID["\(platform.rawValue):\(record.平台ID)"] {
            record.malID = malID
        }
    }

    /// 作品在各平台上已经知道的 ID：资料库、各平台读到的记录、MAL ID 和编号本身。
    private static func 已知ID(_ operation: 推送操作, session: 同步会话) -> [资料库平台: String] {
        var ids = session.本地[operation.键]?.平台ID ?? [:]
        for (platform, library) in session.平台 {
            if let record = library.记录[operation.键] { ids[platform] = record.平台ID }
        }
        if let malID = operation.malID { ids[.myAnimeList] = String(malID) }
        // “bangumi-anime:123”这类编号本身就带着平台 ID
        if let colon = operation.键.firstIndex(of: ":") {
            let prefix = operation.键[..<colon]
            let id = String(operation.键[operation.键.index(after: colon)...])
            if let dash = prefix.firstIndex(of: "-") {
                let name = String(prefix[..<dash])
                if name == "mal" { ids[.myAnimeList] = ids[.myAnimeList] ?? id }
                else if let platform = 资料库平台(rawValue: name) { ids[platform] = ids[platform] ?? id }
            }
        }
        ids[.vndb] = nil
        ids[operation.平台] = nil
        return ids
    }

    private func 填入已查到的ID(_ session: inout 同步会话) {
        for index in session.推送.indices where session.推送[index].平台ID == nil {
            let operation = session.推送[index]
            session.推送[index].平台ID = session.查找到的ID[operation.平台]?[operation.键]
        }
    }

    private func 执行(_ session: 同步会话) async {
        guard let owner = 本地资料库.shared.所有者, 本地资料库.shared.可写入 else { return }
        待处理 = nil
        显示待处理 = false

        let operations = session.推送.filter { $0.平台ID != nil }
        var failed: Set<String> = []
        var errors: [资料库平台: String] = [:]
        for platform in session.平台.keys {
            let total = operations.filter { $0.平台 == platform }.count
            // 没有要写入的平台直接显示完成，不用等其他平台写完
            任务[platform]?.状态 = total > 0 ? .进行中(已完成: 0, 总数: total) : .完成(.now)
        }

        // 各平台同时写入；同一平台内按顺序写，避免触发平台的请求频率限制
        let byPlatform = Dictionary(grouping: operations, by: \.平台)
        let workers = byPlatform.map { platform, platformOperations in
            Task { () -> (Set<String>, String?) in
                var platformFailed: Set<String> = []
                var firstError: String?
                for (index, operation) in platformOperations.enumerated() {
                    do {
                        try await self.写入(operation)
                    } catch {
                        platformFailed.insert(operation.id)
                        firstError = firstError ?? Self.错误说明(error)
                    }
                    if case let .进行中(_, total) = self.任务[platform]?.状态 {
                        self.任务[platform]?.状态 = .进行中(已完成: index + 1, 总数: total)
                    }
                }
                return (platformFailed, firstError)
            }
        }
        for (platform, worker) in zip(byPlatform.keys, workers) {
            let (platformFailed, firstError) = await worker.value
            failed.formUnion(platformFailed)
            if let firstError { errors[platform] = firstError }
        }
        // 改回 AniList 自动填写的日期。失败了也不要紧：下次同步还会认出来再改
        if let account = aniList, account.isLoggedIn {
            for (key, fix) in session.AniList日期修正 {
                guard let value = session.平台[.aniList]?.记录[key]?.平台ID, let mediaID = Int(value) else { continue }
                try? await account.修改日期(mediaID: mediaID, 日期: fix)
            }
        }

        // 新的资料库：没有推送成功的新增，平台 ID 不写进去
        var session = session
        session.推送 = session.推送.map { operation in
            var operation = operation
            if failed.contains(operation.id) { operation.平台ID = nil }
            return operation
        }
        var library = 同步合并.新资料库(session)
        for operation in session.推送 where operation.种类 == .新增 {
            if let id = operation.平台ID { library[operation.键]?.平台ID[operation.平台] = id }
        }

        var store = 同步状态存储.读取(owner: owner)
        let previousBases = store.基线
        store.基线.merge(同步合并.新基线(session, 失败: failed)) { _, new in new }
        // 以前隐藏的作品不在这次的数据里，保留它们原来的基线
        for key in store.隐藏.keys {
            for platform in session.平台.keys {
                if let value = previousBases[platform]?.快照[key] { store.基线[platform]?.快照[key] = value }
            }
        }
        for (key, platforms) in session.新隐藏 {
            store.隐藏[key, default: []].formUnion(platforms)
            if let entry = session.本地[key] ?? 同步合并.隐藏条目(key: key, session: session) {
                store.隐藏条目[key] = entry
            }
        }
        // 平台上的修改已经推送：成功的从待推送中移除，失败或没找到的留到下次
        var pending = session.待推送
        for key in Set(pending.keys) {
            for platform in session.平台.keys {
                let failedHere = failed.contains("\(platform.rawValue)|\(key)")
                    || session.未匹配[platform]?.contains(key) == true
                if !failedHere { pending[key]?.remove(platform) }
            }
            if pending[key]?.isEmpty == true { pending[key] = nil }
        }
        for operation in session.推送 where failed.contains(operation.id) {
            pending[operation.键, default: []].insert(operation.平台)
        }
        store.待推送 = pending
        // 这次同步决定删除的作品（覆盖、确认删除）记下来：不能删除的平台上还留着它，以后不能再恢复回来
        for (key, result) in session.结果 where result == .删除 {
            store.本地已删除.insert(key)
        }

        // 在 MAL 上按标题搜到、成功添加的作品：资料库里的编号改成 MAL 的，并记住平台记录和 MAL ID 的对应，
        // 否则下次同步时 MAL 那边按 MAL ID 编号，又会被当成另一部作品
        for operation in session.推送 where operation.平台 == .myAnimeList && operation.种类 == .新增
            && !failed.contains(operation.id) && !operation.键.hasPrefix("mal-") {
            guard let value = operation.平台ID, let malID = Int(value) else { continue }
            let newKey = 同步合并.键(类型: operation.类型, malID: malID, 平台: .myAnimeList, 平台ID: value)
            for (platform, platformLibrary) in session.平台 {
                if let record = platformLibrary.记录[operation.键] {
                    store.已知MALID["\(platform.rawValue):\(record.平台ID)"] = malID
                }
                if let baseValue = store.基线[platform]?.快照.removeValue(forKey: operation.键) {
                    store.基线[platform]?.快照[newKey] = baseValue
                }
            }
            if var entry = library.removeValue(forKey: operation.键) {
                entry.id = newKey
                entry.平台ID[.myAnimeList] = value
                library[newKey] = entry
            }
        }
        // 找不到的作品记下来，可以在同步任务里手动匹配；新出现的匿名提交到后台
        var newlyUnmatched: [(未匹配作品, 资料库平台)] = []
        for platform in session.平台.keys {
            let works = (session.未匹配[platform] ?? []).compactMap { key -> 未匹配作品? in
                guard let operation = session.推送.first(where: { $0.平台 == platform && $0.键 == key }) else { return nil }
                return PaperVN.未匹配作品(
                    键: key,
                    类型: operation.类型,
                    标题: operation.标题,
                    全部标题: (operation.全部标题 + [operation.日文标题].compactMap { $0 }).reduce(into: [String]()) { titles, title in
                        if title != operation.标题 && !titles.contains(title) { titles.append(title) }
                    },
                    年份: operation.年份,
                    已知ID: Self.已知ID(operation, session: session)
                )
            }
            store.未匹配作品[platform] = works.isEmpty ? nil : works
            for work in works where !store.已提交未匹配.contains("\(platform.rawValue)|\(work.键)") {
                newlyUnmatched.append((work, platform))
            }
        }
        本地资料库.shared.替换动画漫画(Array(library.values), owner: owner)
        store.保存(owner: owner)
        if !newlyUnmatched.isEmpty {
            Task {
                let items = newlyUnmatched.map { 作品匹配校准.提交项($0.0, 平台: $0.1) }
                guard await 作品匹配校准.shared.提交(items), 本地资料库.shared.所有者 == owner else { return }
                var store = 同步状态存储.读取(owner: owner)
                store.已提交未匹配.formUnion(newlyUnmatched.map { "\($0.1.rawValue)|\($0.0.键)" })
                store.保存(owner: owner)
            }
        }

        未匹配作品 = store.未匹配作品
        隐藏数 = store.隐藏条目.count
        for platform in session.平台.keys {
            if let message = errors[platform] {
                任务[platform]?.状态 = .失败(message)
            } else {
                任务[platform]?.状态 = .完成(.now)
                Self.记录同步完成(platform)
            }
        }
    }

    private func 写入(_ operation: 推送操作) async throws {
        guard let platformID = operation.平台ID else { return }
        let 日期修正 = (原有: operation.平台原有日期, 期望: operation.资料库日期)
        do {
            try await 写入(operation.平台, platformID: platformID, type: operation.类型, target: operation.目标, 自动日期修正: 日期修正)
        } catch let 平台账户错误.rateLimited(_, retryAfter) {
            // AniList 每分钟限制请求次数，等一会儿再试一次
            try await Task.sleep(for: .seconds(min(retryAfter, 90)))
            try await 写入(operation.平台, platformID: platformID, type: operation.类型, target: operation.目标, 自动日期修正: 日期修正)
        }
    }

    /// 开始、完成日期（“2024-05-31”）。只在 App 里编辑日期时推送，同步合并不比较日期。
    struct 推送日期: Equatable {
        var 开始: String?
        var 完成: String?
    }

    /// `清除空值`：在编辑页存储时为真，没有评分表示清除评分；同步时为假，没有的评分保持平台上原样。
    /// 进度为空时任何情况下都不写入，不会把平台上的进度改成 0。
    private func 写入(
        _ platform: 资料库平台,
        platformID: String,
        type: 作品类型,
        target: 同步快照?,
        日期: 推送日期? = nil,
        清除空值: Bool = false,
        自动日期修正: (原有: 同步日期, 期望: 同步日期)? = nil
    ) async throws {
        switch platform {
        case .myAnimeList:
            // 账户不在或 ID 不对时必须报错：静默返回会被当成写入成功，并记进基线
            guard let account = myAnimeList, account.isLoggedIn else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            guard let id = Int(platformID) else { throw 平台账户错误.invalidResponse(platform.localizedTitle) }
            let kind: MyAnimeList列表项.种类 = type == .anime ? .anime : .manga
            if let target {
                try await account.updateListStatus(
                    kind: kind, id: id, status: target.状态,
                    score: target.评分 ?? (清除空值 ? 0 : nil),
                    progress: target.进度,
                    dates: 日期.map { ($0.开始, $0.完成) }
                )
            } else {
                try await account.deleteListItem(kind: kind, id: id)
            }
        case .aniList:
            guard let account = aniList, account.isLoggedIn else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            guard let id = Int(platformID) else { throw 平台账户错误.invalidResponse(platform.localizedTitle) }
            if let target {
                try await account.保存(
                    mediaID: id, 快照: target, 日期: 日期.map { ($0.开始, $0.完成) }, 清除空值: 清除空值, 自动日期修正: 自动日期修正
                )
            } else {
                try await account.删除(mediaID: id)
            }
        case .annict:
            guard let account = annict, account.isLoggedIn else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            try await account.设置状态(workID: platformID, 状态: target?.状态)
        case .tmdb:
            guard let account = tmdb, account.isLoggedIn else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            try await account.写入(平台ID: platformID, 快照: target)
        case .bangumi:
            // Bangumi 没有删除收藏的接口，删除不会推送
            guard let target else { return }
            guard let account = bangumi, account.isLoggedIn else { throw 平台账户错误.notLoggedIn(platform.localizedTitle) }
            guard let id = Int(platformID) else { throw 平台账户错误.invalidResponse(platform.localizedTitle) }
            try await account.保存收藏(subjectID: id, 类型: type, 快照: target, 清除空值: 清除空值)
        default:
            return
        }
    }

    // MARK: 在 App 里修改

    /// 先改本地资料库，再推送到各平台。推送失败的平台记进待推送，下次同步时再推送，本地的修改不会丢。
    func 修改(_ entry: 本地资料库条目, 状态 newStatus: 资料库状态? = nil, 进度 newProgress: Int? = nil) async throws {
        var updated = entry
        if let newStatus { updated.状态 = newStatus }
        if let newProgress { updated.进度 = max(0, newProgress) }
        本地资料库.shared.更新(updated)
        try await 推送单项(updated, 目标: 同步合并.快照(updated))
    }

    /// 编辑页存储：本地先存，再推送状态、评分、进度；日期改过时一起推送到支持日期的平台（MAL、AniList）。
    func 存储(_ entry: 本地资料库条目, 推送日期 pushDates: Bool) async throws {
        本地资料库.shared.更新(entry)
        try await 推送单项(
            entry,
            目标: 同步合并.快照(entry),
            日期: pushDates ? 推送日期(开始: entry.开始日期, 完成: entry.完成日期) : nil,
            清除空值: true
        )
    }

    /// 加入资料库（例如在详情页加入计划）。
    func 添加(_ entry: 本地资料库条目) async throws {
        本地资料库.shared.添加(entry)
        try await 推送单项(entry, 目标: 同步合并.快照(entry))
    }

    /// 从资料库和所有已登录的平台删除。
    func 删除(_ entry: 本地资料库条目) async throws {
        本地资料库.shared.删除(id: entry.id)
        try await 推送单项(entry, 目标: nil)
    }

    /// `清除空值` 只在编辑页存储时为真：那里每一项都是用户明确设置的。
    /// 快捷修改状态、进度时为假，资料库里没有的评分、进度不会把平台上的值清空。
    private func 推送单项(
        _ entry: 本地资料库条目,
        目标 target: 同步快照?,
        日期: 推送日期? = nil,
        清除空值: Bool = false
    ) async throws {
        guard Self.已启用, let owner = 本地资料库.shared.所有者 else { return }
        // 只导入的平台（Bangumi）不写入
        let platforms = 已登录平台.filter { $0.可导出 && $0.同步能力.支持的类型.contains(entry.类型) }

        // 已看完而不知道集数时按总集数写，不留空
        var target = target
        if target?.状态 == .completed, target?.进度 == nil, let total = entry.总数 { target?.进度 = total }

        var store = 同步状态存储.读取(owner: owner)
        store.待推送[entry.id, default: []].formUnion(platforms)
        // 记住在 PaperVN 中删除的作品：Bangumi 上还留着它，同步时不能再恢复回来。只登录了 Bangumi 时也要记
        if target == nil {
            store.本地已删除.insert(entry.id)
        } else {
            store.本地已删除.remove(entry.id)
        }
        store.保存(owner: owner)
        guard !platforms.isEmpty else { return }

        var firstError: Error?
        // 没有改日期时，平台上的日期按和资料库一致看待：AniList 自动填上的日期改回资料库里的
        let 本地日期 = 同步日期(开始: entry.开始日期, 完成: entry.完成日期)
        for platform in platforms {
            let platformID = entry.平台ID[platform]
                ?? (platform == .myAnimeList ? entry.malID.map(String.init) : nil)
                ?? 作品映射.平台ID(entry.id, 平台: platform, 类型: entry.类型)
            // 平台不支持删除（Bangumi）：不推送，需要用户在平台上手动删除
            if target == nil && !platform.同步能力.支持删除 {
                store.待推送[entry.id]?.remove(platform)
                continue
            }
            // 还不知道作品在该平台上的 ID：留在待推送里，完整同步时查找后再推送
            guard let platformID else { continue }
            do {
                try await 写入(
                    platform, platformID: platformID, type: entry.类型, target: target, 日期: 日期, 清除空值: 清除空值,
                    自动日期修正: 日期 == nil ? (原有: 本地日期, 期望: 本地日期) : nil
                )
                store.待推送[entry.id]?.remove(platform)
                if store.基线[platform] != nil {
                    let existing = store.基线[platform]?.快照[entry.id]
                    // TMDB 记录不了的值写入后作品会从 TMDB 上消失，基线里也去掉，免得下次被当成在 TMDB 上删除
                    store.基线[platform]?.快照[entry.id] = target.flatMap { value in
                        platform.同步能力.可记录(value)
                            ? 同步合并.平台保存的值(value, 现有: existing, platform: platform, type: entry.类型)
                            : nil
                    }
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        if store.待推送[entry.id]?.isEmpty == true { store.待推送[entry.id] = nil }
        store.保存(owner: owner)
        if let firstError { throw firstError }
    }

    /// 退出登录时清空任务与当前资料库。
    func 重置() {
        vndb导入标识 = nil
        vndb导入?.cancel()
        vndb导入 = nil
        动画同步?.cancel()
        动画同步 = nil
        待处理 = nil
        上一步 = []
        显示待处理 = false
        上次凭据 = nil
        任务 = [:]
        未匹配作品 = [:]
        读取失败 = [:]
        隐藏数 = 0
        最近同步时间 = [:]
        UserDefaults.standard.removeObject(forKey: Self.最近同步时间键)
        本地资料库.shared.切换所有者(nil)
    }

    private static func 错误说明(_ error: Error) -> String {
        if error as? VNDB服务错误 == .token无效
            || (error as? URLError)?.code == .userAuthenticationRequired {
            return String(localized: "资料库请求未通过登录验证，请稍后再试。")
        }
        return error.localizedDescription
    }
}

/// 各平台的基线与待推送的修改，按资料库所有者保存在应用支持目录中。
struct 同步状态存储: Codable {
    var 基线: [资料库平台: 平台基线] = [:]
    var 待推送: [String: Set<资料库平台>] = [:]
    /// 分别保留时隐藏的作品与它们所在的平台。
    var 隐藏: [String: Set<资料库平台>] = [:]
    /// 隐藏的作品在隐藏时的记录，重新显示时加回资料库。
    var 隐藏条目: [String: 本地资料库条目] = [:]
    /// 在 PaperVN 中删除的作品。
    var 本地已删除: Set<String> = []
    /// 在 MAL 上按标题搜到的对应关系：“平台:平台上的作品 ID” → MAL ID。
    var 已知MALID: [String: Int] = [:]
    var 已清理误恢复的作品 = false
    /// 各平台上找不到、没有同步过去的作品。
    var 未匹配作品: [资料库平台: [未匹配作品]] = [:]
    /// 已经提交到后台的未匹配作品（“平台|编号”），不重复提交。
    var 已提交未匹配: Set<String> = []
    /// 用户手动匹配的作品，优先于校准表。
    var 手动匹配: [作品对应组] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        基线 = try container.decodeIfPresent([资料库平台: 平台基线].self, forKey: .基线) ?? [:]
        待推送 = try container.decodeIfPresent([String: Set<资料库平台>].self, forKey: .待推送) ?? [:]
        隐藏 = try container.decodeIfPresent([String: Set<资料库平台>].self, forKey: .隐藏) ?? [:]
        隐藏条目 = try container.decodeIfPresent([String: 本地资料库条目].self, forKey: .隐藏条目) ?? [:]
        本地已删除 = try container.decodeIfPresent(Set<String>.self, forKey: .本地已删除) ?? []
        已知MALID = try container.decodeIfPresent([String: Int].self, forKey: .已知MALID) ?? [:]
        已清理误恢复的作品 = try container.decodeIfPresent(Bool.self, forKey: .已清理误恢复的作品) ?? false
        未匹配作品 = try container.decodeIfPresent([资料库平台: [PaperVN.未匹配作品]].self, forKey: .未匹配作品) ?? [:]
        已提交未匹配 = try container.decodeIfPresent(Set<String>.self, forKey: .已提交未匹配) ?? []
        手动匹配 = try container.decodeIfPresent([作品对应组].self, forKey: .手动匹配) ?? []
    }

    static func 读取(owner: String) -> 同步状态存储 {
        guard let data = try? Data(contentsOf: 文件地址(owner: owner)),
              let value = try? JSONDecoder().decode(同步状态存储.self, from: data) else {
            return 同步状态存储()
        }
        return value
    }

    func 保存(owner: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let url = Self.文件地址(owner: owner)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func 文件地址(owner: String) -> URL {
        let safeOwner = owner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner
        return URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "\(safeOwner).json")
    }
}


#if DEBUG
extension PaperVNSync中心 {
    /// 预览用：直接设定同步状态，不读取平台、不写入磁盘。每个预览都完整设定一次，互不影响。
    func 预览设置(
        待处理 session: 同步会话? = nil,
        任务 tasks: [资料库平台: 任务状态] = [:],
        最近同步时间 times: [资料库平台: Date] = [:],
        上一步 previous: [同步会话] = [],
        未匹配作品 unmatched: [资料库平台: [未匹配作品]] = [:],
        读取失败 failures: [资料库平台: String] = [:],
        隐藏数 hidden: Int = 0
    ) {
        待处理 = session
        显示待处理 = false
        任务 = Dictionary(uniqueKeysWithValues: tasks.map { platform, state in
            (platform, 同步任务(平台: platform, 标题: platform.localizedTitle, 状态: state))
        })
        最近同步时间 = times
        上一步 = previous
        未匹配作品 = unmatched
        读取失败 = failures
        隐藏数 = hidden
    }
}
#endif
