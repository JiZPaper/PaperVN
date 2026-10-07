import Combine
@preconcurrency import DeclaredAgeRange
import Foundation
import OSLog
import FamilyControls

enum 家庭控制授权状态: String, Sendable {
    case notDetermined
    case denied
    case approved
    case approvedWithDataAccess

    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }

    var localizedTitle: String {
        switch self {
        case .notDetermined:
            return String(localized: "尚未请求")
        case .denied:
            return String(localized: "未授权")
        case .approved:
            return String(localized: "已授权")
        case .approvedWithDataAccess:
            return String(localized: "已授权并允许数据访问")
        }
    }
}

enum 家长年龄级别: Int, Codable, Comparable, Sendable {
    case unknown = 0
    case adult = 1
    case teen16To17 = 2
    case teen13To15 = 3
    case childUnder13 = 4

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var requiresEnforcement: Bool {
        self >= .teen16To17
    }

    var localizedTitle: String {
        switch self {
        case .unknown:
            return String(localized: "年龄范围未共享")
        case .adult:
            return String(localized: "成年人")
        case .teen16To17:
            return String(localized: "16～17岁")
        case .teen13To15:
            return String(localized: "13～15岁")
        case .childUnder13:
            return String(localized: "未满13岁")
        }
    }

    static func resolve(
        lowerBound: Int?,
        upperBound: Int?,
        hasActiveParentalControls: Bool
    ) -> Self {
        if let upperBound {
            if upperBound < 13 { return .childUnder13 }
            if upperBound < 16 { return .teen13To15 }
            if upperBound < 18 { return .teen16To17 }
        }

        if let lowerBound, lowerBound >= 18 {
            return hasActiveParentalControls ? .teen16To17 : .adult
        }

        if let lowerBound {
            if lowerBound < 13 { return .childUnder13 }
            if lowerBound < 16 { return .teen13To15 }
            if lowerBound < 18 { return .teen16To17 }
        }

        return hasActiveParentalControls ? .teen16To17 : .unknown
    }
}

struct 家长内容策略: Equatable, Sendable {
    let isEnforced: Bool
    let sexualThreshold: Double
    let violenceThreshold: Double
    let blocksRestrictedContentReveal: Bool
    let blocksUntrustedExternalLinks: Bool

    static let unrestricted = 家长内容策略(
        isEnforced: false,
        sexualThreshold: 2,
        violenceThreshold: 2,
        blocksRestrictedContentReveal: false,
        blocksUntrustedExternalLinks: false
    )

    static func policy(
        ageLevel: 家长年龄级别,
        familyChildAuthorized: Bool
    ) -> Self {
        let effectiveLevel = familyChildAuthorized
            ? max(ageLevel, .teen16To17)
            : ageLevel

        switch effectiveLevel {
        case .unknown, .adult:
            return .unrestricted
        case .teen16To17:
            return 家长内容策略(
                isEnforced: true,
                sexualThreshold: 1,
                violenceThreshold: 1,
                blocksRestrictedContentReveal: true,
                blocksUntrustedExternalLinks: true
            )
        case .teen13To15:
            return 家长内容策略(
                isEnforced: true,
                sexualThreshold: 0.5,
                violenceThreshold: 0.5,
                blocksRestrictedContentReveal: true,
                blocksUntrustedExternalLinks: true
            )
        case .childUnder13:
            return 家长内容策略(
                isEnforced: true,
                sexualThreshold: 0,
                violenceThreshold: 0,
                blocksRestrictedContentReveal: true,
                blocksUntrustedExternalLinks: true
            )
        }
    }
}

@MainActor
final class 家长控制中心: ObservableObject {
    static let shared = 家长控制中心()

    private static let logger = Logger(
        subsystem: "com.jizpaper.PaperVN",
        category: "FamilyControls"
    )

    @Published private(set) var familyAuthorizationStatus: 家庭控制授权状态
    @Published private(set) var ageLevel: 家长年龄级别
    @Published private(set) var ageRangeWasDeclined: Bool
    @Published private(set) var ageRangeLowerBound: Int?
    @Published private(set) var ageRangeUpperBound: Int?
    @Published private(set) var ageDeclarationDescription: String?
    @Published private(set) var hasActiveParentalControls: Bool
    @Published private(set) var policy: 家长内容策略
    @Published private(set) var isRequestingFamilyAuthorization = false
    @Published private(set) var lastErrorMessage: String?

    private enum Key {
        static let ageLevel = "parentalControls.ageLevel"
        static let ageRangeWasDeclined = "parentalControls.ageRangeWasDeclined"
        static let ageRangeLowerBound = "parentalControls.ageRangeLowerBound"
        static let ageRangeUpperBound = "parentalControls.ageRangeUpperBound"
        static let ageDeclaration = "parentalControls.ageDeclaration"
        static let hasActiveParentalControls = "parentalControls.hasActiveParentalControls"
        static let familyChildAuthorizationWasRequested =
            "parentalControls.familyChildAuthorizationWasRequested"
        static let hasBackedUpUserPreferences =
            "parentalControls.hasBackedUpUserPreferences"
        static let backupEnabled = "parentalControls.backup.contentFilterEnabled"
        static let backupSexualThreshold = "parentalControls.backup.sexualThreshold"
        static let backupViolenceThreshold = "parentalControls.backup.violenceThreshold"
        static let backupFilterMode = "parentalControls.backup.filterMode"
        static let backupRestrictionMethod =
            "parentalControls.backup.contentRestrictionMethod"
    }

    private enum ContentKey {
        static let enabled = "contentFilterEnabled"
        static let sexualThreshold = "sexualThreshold"
        static let violenceThreshold = "violenceThreshold"
        static let filterMode = "filterMode"
        static let restrictionMethod = "contentRestrictionMethod"
    }

    private let defaults: UserDefaults
    private var defaultsObserver: AnyCancellable?
    private var familyAuthorizationObserver: AnyCancellable?
    private var isNormalizingSettings = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedAgeLevel = 家长年龄级别(
            rawValue: defaults.integer(forKey: Key.ageLevel)
        ) ?? .unknown
        ageLevel = storedAgeLevel
        ageRangeWasDeclined = defaults.bool(forKey: Key.ageRangeWasDeclined)
        ageRangeLowerBound = Self.optionalInteger(
            forKey: Key.ageRangeLowerBound,
            defaults: defaults
        )
        ageRangeUpperBound = Self.optionalInteger(
            forKey: Key.ageRangeUpperBound,
            defaults: defaults
        )
        ageDeclarationDescription = defaults.string(forKey: Key.ageDeclaration)
        hasActiveParentalControls = defaults.bool(
            forKey: Key.hasActiveParentalControls
        )

        familyAuthorizationStatus = .notDetermined

        policy = 家长内容策略.policy(
            ageLevel: storedAgeLevel,
            familyChildAuthorized: false
        )

        refreshFamilyAuthorizationStatus()
        recomputePolicyAndNormalizeSettings()

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: defaults
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.normalizeContentSettingsIfNeeded(
                reapplyFromUserPreferences: false
            )
        }

        familyAuthorizationObserver = AuthorizationCenter.shared
            .$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                refreshFamilyAuthorizationStatus()
                recomputePolicyAndNormalizeSettings()
            }
    }

    var canRequestFamilyAuthorization: Bool {
        true
    }

    var familyChildAuthorizationIsActive: Bool {
        familyAuthorizationStatus.isApproved
            && defaults.bool(forKey: Key.familyChildAuthorizationWasRequested)
    }

    var canRevealRestrictedContent: Bool {
        !policy.blocksRestrictedContentReveal
    }

    var statusSummary: String {
        if familyChildAuthorizationIsActive {
            return String(localized: "家长控制")
        }
        if policy.isEnforced {
            return String(localized: "按照共享年龄范围控制")
        }
        if ageRangeWasDeclined {
            return String(localized: "使用当前用户设置")
        }
        return String(localized: "使用当前用户设置")
    }

    func refresh() {
        refreshFamilyAuthorizationStatus()
        recomputePolicyAndNormalizeSettings()
    }

    func synchronizeFamilyAuthorizationAtLaunch() async {
        guard !isRequestingFamilyAuthorization,
              familyAuthorizationStatus == .notDetermined else { return }
        await requestFamilyAuthorizationForChild(reportErrors: false)
    }

    func requestFamilyAuthorizationForChild(reportErrors: Bool = true) async {
        guard !isRequestingFamilyAuthorization else { return }
        isRequestingFamilyAuthorization = true
        lastErrorMessage = nil
        defer { isRequestingFamilyAuthorization = false }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            defaults.set(
                true,
                forKey: Key.familyChildAuthorizationWasRequested
            )
            refreshFamilyAuthorizationStatus()
            recomputePolicyAndNormalizeSettings()
        } catch is CancellationError {
            refreshFamilyAuthorizationStatus()
        } catch let error as FamilyControlsError
            where error == .authorizationCanceled {
            refreshFamilyAuthorizationStatus()
        } catch {
            refreshFamilyAuthorizationStatus()
            if familyAuthorizationStatus.isApproved {
                recomputePolicyAndNormalizeSettings()
            } else if reportErrors {
                lastErrorMessage = Self.familyAuthorizationErrorMessage(for: error)
                Self.logger.error(
                    "Child authorization failed: \(String(describing: error), privacy: .public)"
                )
            } else {
                Self.logger.debug(
                    "Child authorization synchronization did not complete: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    @available(iOS 26.0, *)
    func applyDeclaredAgeRangeResponse(
        _ response: AgeRangeService.Response
    ) {
        lastErrorMessage = nil

        switch response {
        case .declinedSharing:
            ageRangeWasDeclined = true
            defaults.set(true, forKey: Key.ageRangeWasDeclined)

        case let .sharing(range):
            ageRangeWasDeclined = false
            ageRangeLowerBound = range.lowerBound
            ageRangeUpperBound = range.upperBound
            hasActiveParentalControls = !range.activeParentalControls.isEmpty
            ageDeclarationDescription = Self.declarationDescription(
                range.ageRangeDeclaration
            )
            ageLevel = 家长年龄级别.resolve(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound,
                hasActiveParentalControls: hasActiveParentalControls
            )

            defaults.set(false, forKey: Key.ageRangeWasDeclined)
            Self.setOptionalInteger(
                range.lowerBound,
                forKey: Key.ageRangeLowerBound,
                defaults: defaults
            )
            Self.setOptionalInteger(
                range.upperBound,
                forKey: Key.ageRangeUpperBound,
                defaults: defaults
            )
            defaults.set(ageLevel.rawValue, forKey: Key.ageLevel)
            defaults.set(
                hasActiveParentalControls,
                forKey: Key.hasActiveParentalControls
            )
            defaults.set(
                ageDeclarationDescription,
                forKey: Key.ageDeclaration
            )
        @unknown default:
            lastErrorMessage = String(localized: "系统返回了无法识别的年龄范围结果。")
        }

        recomputePolicyAndNormalizeSettings()
    }

    func recordAgeRangeRequestError(_ error: Error) {
        guard !(error is CancellationError) else { return }
        lastErrorMessage = String(
            localized: "无法获取共享的年龄范围。请稍后再试，或检查系统中的年龄范围共享设置。"
        )
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func allowsExternalURL(_ url: URL) -> Bool {
        Self.allowsExternalURL(url, policy: policy)
    }

    nonisolated static func allowsExternalURL(
        _ url: URL,
        policy: 家长内容策略
    ) -> Bool {
        guard policy.blocksUntrustedExternalLinks else { return true }
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "papervn.jizpaper.com"
            && ["/PrivacyPolicy.html", "/TermsOfService.html"]
                .contains(url.path)
    }

    private func refreshFamilyAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        if #available(iOS 26.4, *), status == .approvedWithDataAccess {
            familyAuthorizationStatus = .approvedWithDataAccess
        } else {
            switch status {
            case .notDetermined:
                familyAuthorizationStatus = .notDetermined
            case .denied:
                familyAuthorizationStatus = .denied
            case .approved:
                familyAuthorizationStatus = .approved
            case .approvedWithDataAccess:
                familyAuthorizationStatus = .approvedWithDataAccess
            @unknown default:
                familyAuthorizationStatus = .notDetermined
            }
        }
    }

    private static func familyAuthorizationErrorMessage(for error: Error) -> String {
        guard let familyError = error as? FamilyControlsError else {
            return String(
                localized: "无法完成儿童账户授权。请确认当前Apple账户属于家庭中的儿童成员后再试。"
            )
        }

        switch familyError {
        case .networkError, .unavailable:
            return String(
                localized: "无法完成儿童账户授权。请稍后再试，并确认设备已联网且当前Apple账户属于家庭中的儿童成员。"
            )
        default:
            return String(
                localized: "无法完成儿童账户授权。请确认当前Apple账户属于家庭中的儿童成员后再试。"
            )
        }
    }

    private func recomputePolicyAndNormalizeSettings() {
        policy = 家长内容策略.policy(
            ageLevel: ageLevel,
            familyChildAuthorized: familyChildAuthorizationIsActive
        )
        normalizeContentSettingsIfNeeded(reapplyFromUserPreferences: true)
    }

    private func normalizeContentSettingsIfNeeded(
        reapplyFromUserPreferences: Bool
    ) {
        guard !isNormalizingSettings else { return }
        isNormalizingSettings = true
        defer { isNormalizingSettings = false }

        if 紧急回避设置.会话正在进行(defaults: defaults) {
            紧急回避设置.应用最严格限制(to: defaults)
            return
        }

        if policy.isEnforced {
            backUpUserPreferencesIfNeeded()
            let preferredSexualThreshold = reapplyFromUserPreferences
                ? defaults.double(forKey: Key.backupSexualThreshold)
                : defaults.object(forKey: ContentKey.sexualThreshold) as? Double
                    ?? policy.sexualThreshold
            let preferredViolenceThreshold = reapplyFromUserPreferences
                ? defaults.double(forKey: Key.backupViolenceThreshold)
                : defaults.object(forKey: ContentKey.violenceThreshold) as? Double
                    ?? policy.violenceThreshold

            setIfChanged(true, forKey: ContentKey.enabled)
            setIfChanged(
                min(preferredSexualThreshold, policy.sexualThreshold),
                forKey: ContentKey.sexualThreshold
            )
            setIfChanged(
                min(preferredViolenceThreshold, policy.violenceThreshold),
                forKey: ContentKey.violenceThreshold
            )
            setIfChanged("色情与暴力", forKey: ContentKey.filterMode)
            setIfChanged("hidden", forKey: ContentKey.restrictionMethod)
        } else {
            restoreUserPreferencesIfNeeded()
        }

        强制内容安全策略.应用到用户设置(defaults)
    }

    private func backUpUserPreferencesIfNeeded() {
        guard !defaults.bool(forKey: Key.hasBackedUpUserPreferences) else {
            return
        }

        defaults.set(
            defaults.object(forKey: ContentKey.enabled) as? Bool ?? false,
            forKey: Key.backupEnabled
        )
        defaults.set(
            defaults.object(forKey: ContentKey.sexualThreshold) as? Double ?? 0.8,
            forKey: Key.backupSexualThreshold
        )
        defaults.set(
            defaults.object(forKey: ContentKey.violenceThreshold) as? Double ?? 1,
            forKey: Key.backupViolenceThreshold
        )
        defaults.set(
            defaults.string(forKey: ContentKey.filterMode) ?? "色情与暴力",
            forKey: Key.backupFilterMode
        )
        defaults.set(
            defaults.string(forKey: ContentKey.restrictionMethod) ?? "blurred",
            forKey: Key.backupRestrictionMethod
        )
        defaults.set(true, forKey: Key.hasBackedUpUserPreferences)
    }

    private func restoreUserPreferencesIfNeeded() {
        guard defaults.bool(forKey: Key.hasBackedUpUserPreferences) else {
            return
        }

        defaults.set(defaults.bool(forKey: Key.backupEnabled), forKey: ContentKey.enabled)
        defaults.set(
            defaults.double(forKey: Key.backupSexualThreshold),
            forKey: ContentKey.sexualThreshold
        )
        defaults.set(
            defaults.double(forKey: Key.backupViolenceThreshold),
            forKey: ContentKey.violenceThreshold
        )
        defaults.set(
            defaults.string(forKey: Key.backupFilterMode) ?? "色情与暴力",
            forKey: ContentKey.filterMode
        )
        defaults.set(
            defaults.string(forKey: Key.backupRestrictionMethod) ?? "blurred",
            forKey: ContentKey.restrictionMethod
        )
        defaults.set(false, forKey: Key.hasBackedUpUserPreferences)
    }

    private func setIfChanged(_ value: Bool, forKey key: String) {
        guard defaults.object(forKey: key) as? Bool != value else { return }
        defaults.set(value, forKey: key)
    }

    private func setIfChanged(_ value: Double, forKey key: String) {
        guard defaults.object(forKey: key) as? Double != value else { return }
        defaults.set(value, forKey: key)
    }

    private func setIfChanged(_ value: String, forKey key: String) {
        guard defaults.string(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
    }

    @available(iOS 26.0, *)
    private static func declarationDescription(
        _ declaration: AgeRangeService.AgeRangeDeclaration?
    ) -> String? {
        guard let declaration else { return nil }
        if declaration == .selfDeclared {
            return String(localized: "由本人确认")
        }
        if declaration == .guardianDeclared {
            return String(localized: "由家长或监护人确认")
        }
        if #available(iOS 26.5, *), declaration == .confirmed {
            return String(localized: "已确认")
        }
        return String(localized: "已通过系统确认")
    }

    private static func optionalInteger(
        forKey key: String,
        defaults: UserDefaults
    ) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private static func setOptionalInteger(
        _ value: Int?,
        forKey key: String,
        defaults: UserDefaults
    ) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
