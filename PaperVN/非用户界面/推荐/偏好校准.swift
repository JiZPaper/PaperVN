import Combine
import Foundation

struct 偏好校准记录: Codable, Hashable, Identifiable, Sendable {
    let visualNovelID: String
    var score: Int
    var updatedAt: Date
    var visualNovel: 探索视觉小说?

    var id: String { visualNovelID }

    init(
        visualNovelID: String,
        score: Int,
        updatedAt: Date = Date(),
        visualNovel: 探索视觉小说? = nil
    ) {
        self.visualNovelID = visualNovelID
        self.score = min(5, max(1, score))
        self.updatedAt = updatedAt
        self.visualNovel = visualNovel
    }

    var recommendationSignal: Double {
        switch score {
        case 1: return -1
        case 2: return -0.45
        case 3: return 0
        case 4: return 0.45
        default: return 0.85
        }
    }
}

@MainActor
final class 偏好校准中心: ObservableObject {
    static let shared = 偏好校准中心()

    static let iCloud同步设置键 = 偏好数据iCloud同步设置.启用键
    static let 数据变化通知 = Notification.Name(
        "PaperVN.preferenceCalibrationDidChange"
    )

    private static let localStorageKey = "preferenceCalibrationRecordsV1"
    private static let localClearedAtKey = "preferenceCalibrationClearedAtV1"
    private static let cloudStorageKey = "preferenceCalibrationRecordsV1"
    private static let cloudClearedAtKey = "preferenceCalibrationClearedAtV1"

    @Published private(set) var records: [String: 偏好校准记录] = [:]
    private var lastClearedAt: Date?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isICloudSyncEnabled = false

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cloudObserver: NSObjectProtocol?
    private var preferenceSyncObserver: NSObjectProtocol?

    private init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        isICloudSyncEnabled = 偏好数据iCloud同步设置.读取(defaults: defaults)
        records = Self.decodeRecords(
            defaults.data(forKey: Self.localStorageKey),
            decoder: decoder
        )
        lastClearedAt = defaults.object(
            forKey: Self.localClearedAtKey
        ) as? Date
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mergeFromICloudIfEnabled()
            }
        }
        preferenceSyncObserver = NotificationCenter.default.addObserver(
            forName: .paperVNPreferenceICloudSyncSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isICloudSyncEnabled = self.defaults.bool(
                    forKey: Self.iCloud同步设置键
                )
                if self.isICloudSyncEnabled {
                    self.mergeFromICloudIfEnabled()
                    self.uploadToICloud()
                }
            }
        }
        if isICloudSyncEnabled {
            mergeFromICloudIfEnabled()
        }
    }

    var recordCount: Int { records.count }

    func score(for visualNovelID: String) -> Int? {
        records[visualNovelID]?.score
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        isICloudSyncEnabled = enabled
        defaults.set(enabled, forKey: Self.iCloud同步设置键)
        NotificationCenter.default.post(
            name: .paperVNPreferenceICloudSyncSettingDidChange,
            object: nil
        )
        lastSyncError = nil
        if enabled {
            mergeFromICloudIfEnabled()
            uploadToICloud()
        }
    }

    private func persistAndNotify() {
        do {
            let data = try encoder.encode(Array(records.values))
            defaults.set(data, forKey: Self.localStorageKey)
            lastSyncError = nil
            if isICloudSyncEnabled {
                let cloudData = try encoder.encode(Array(records.values))
                cloudStore.set(cloudData, forKey: Self.cloudStorageKey)
                cloudStore.synchronize()
            }
            postChangeNotification()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func uploadToICloud() {
        do {
            let data = try encoder.encode(Array(records.values))
            cloudStore.set(data, forKey: Self.cloudStorageKey)
            if let lastClearedAt {
                cloudStore.set(lastClearedAt, forKey: Self.cloudClearedAtKey)
            }
            cloudStore.synchronize()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func mergeFromICloudIfEnabled() {
        guard isICloudSyncEnabled else { return }
        cloudStore.synchronize()
        let cloudRecords = Self.decodeRecords(
            cloudStore.data(forKey: Self.cloudStorageKey),
            decoder: decoder
        )
        let cloudClearedAt = cloudStore.object(
            forKey: Self.cloudClearedAtKey
        ) as? Date
        let effectiveClearedAt = [lastClearedAt, cloudClearedAt]
            .compactMap { $0 }
            .max()
        if effectiveClearedAt != lastClearedAt {
            lastClearedAt = effectiveClearedAt
            defaults.set(effectiveClearedAt, forKey: Self.localClearedAtKey)
        }

        var merged = records.filter { _, record in
            guard let effectiveClearedAt else { return true }
            return record.updatedAt > effectiveClearedAt
        }
        for (id, record) in cloudRecords {
            if let effectiveClearedAt, record.updatedAt <= effectiveClearedAt {
                continue
            }
            if let local = merged[id], local.updatedAt >= record.updatedAt {
                continue
            }
            merged[id] = record
        }
        guard merged != records else { return }
        records = merged
        persistAndNotify()
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.数据变化通知,
            object: nil
        )
    }

    private static func decodeRecords(
        _ data: Data?,
        decoder: JSONDecoder
    ) -> [String: 偏好校准记录] {
        guard let data,
              let values = try? decoder.decode([偏好校准记录].self, from: data)
        else { return [:] }
        return Dictionary(values.map { ($0.visualNovelID, $0) }) { lhs, rhs in
            lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
    }
}
