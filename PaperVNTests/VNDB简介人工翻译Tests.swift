import Foundation
import Testing
@testable import PaperVN

@Suite
struct VNDB简介人工翻译Tests {
    @Test
    func 千位分桶符合翻译项目目录规则() {
        #expect(VNDB简介人工翻译.bucketName(for: "v3") == "000")
        #expect(VNDB简介人工翻译.bucketName(for: "v20424") == "020")
        #expect(VNDB简介人工翻译.bucketName(for: "c123456") == "123")
        #expect(VNDB简介人工翻译.bucketName(for: "invalid") == nil)
    }

    @Test
    func 读取并清理视觉小说人工译文() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root
            .appending(path: "zh-Hans", directoryHint: .isDirectory)
            .appending(path: "visual-novels", directoryHint: .isDirectory)
            .appending(path: "020", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = Data(
            """
            {
              "schema_version": 1,
              "id": "v20424",
              "type": "visual_novel",
              "language": "zh-Hans",
              "translation": "[url=/c1]人工译文[/url]\\n第二行"
            }
            """.utf8
        )
        try data.write(
            to: directory.appending(
                path: "v20424.json",
                directoryHint: .notDirectory
            )
        )

        let translation = VNDB简介人工翻译.译文(
            for: "v20424",
            type: .visualNovel,
            language: .simplifiedChinese,
            translationsRoot: root
        )

        #expect(translation == "人工译文\n第二行")
    }

    @Test
    func 元数据不匹配时不采用人工译文() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root
            .appending(path: "zh-Hans", directoryHint: .isDirectory)
            .appending(path: "characters", directoryHint: .isDirectory)
            .appending(path: "000", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schema_version": 1,
              "id": "c2",
              "type": "character",
              "language": "zh-Hans",
              "translation": "不应采用"
            }
            """.utf8
        ).write(
            to: directory.appending(
                path: "c1.json",
                directoryHint: .notDirectory
            )
        )

        #expect(
            VNDB简介人工翻译.译文(
                for: "c1",
                type: .character,
                language: .simplifiedChinese,
                translationsRoot: root
            ) == nil
        )
    }

    @Test
    func 大陆特征优先使用PaperVN服务器() {
        #expect(
            VNDB简介翻译数据源.优先顺序(prefersPaperVN: true)
                == [.paperVN, .github]
        )
        #expect(
            VNDB简介翻译数据源.优先顺序(prefersPaperVN: false)
                == [.github, .paperVN]
        )
    }

    @Test
    func 两个数据源使用相同的项目目录结构() throws {
        let path = try #require(
            VNDB简介人工翻译.relativeTranslationPath(
                for: "v20424",
                type: .visualNovel,
                language: .simplifiedChinese
            )
        )
        #expect(path == "zh-Hans/visual-novels/020/v20424.json")
        #expect(
            VNDB简介翻译数据源.github.entryURL(relativePath: path)?.absoluteString
                == "https://raw.githubusercontent.com/JiZPaper/VNDB-Description-Translations/main/zh-Hans/visual-novels/020/v20424.json"
        )
        #expect(
            VNDB简介翻译数据源.paperVN.entryURL(relativePath: path)?.absoluteString
                == "https://papervn.jizpaper.com/translations/vndb-descriptions/zh-Hans/visual-novels/020/v20424.json"
        )
    }

    @Test
    func 投稿语言默认跟随界面语言() {
        #expect(
            简介翻译投稿语言.默认语言(
                interfaceLanguage: "ja",
                fallback: .simplifiedChinese
            ) == .japanese
        )
        #expect(
            简介翻译投稿语言.默认语言(
                interfaceLanguage: "zh-Hant",
                fallback: .simplifiedChinese
            ) == .traditionalChinese
        )
        #expect(
            简介翻译投稿语言.默认语言(
                interfaceLanguage: "de",
                fallback: .japanese
            ) == .japanese
        )
        #expect(
            简介翻译投稿语言.默认语言(
                interfaceLanguage: "en",
                fallback: .korean
            ) == .korean
        )
    }

    @Test
    func 从压缩包注释读取项目提交() throws {
        let revision = "3a4232eb5462595861f68b4d0d3a301e68b21437"
        let cases: [(comment: String, expected: String?)] = [
            (revision.uppercased(), revision),
            ("not a revision", nil),
            ("", nil)
        ]
        for testCase in cases {
            let url = try 写入空压缩包(comment: testCase.comment)
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(VNDB简介人工翻译.压缩包版本号(at: url) == testCase.expected)
        }
    }

    @Test
    func 离线翻译文件只在项目有新版本时提示更新() {
        let downloadedAt = Date(timeIntervalSince1970: 1_000)
        let latest = VNDB简介翻译版本(
            revision: "bbbb",
            committedAt: Date(timeIntervalSince1970: 2_000),
            archiveBytes: 18_382_602
        )

        #expect(
            !VNDB简介人工翻译.需要更新(
                to: latest,
                installedRevision: "BBBB",
                downloadedAt: downloadedAt
            )
        )
        #expect(
            VNDB简介人工翻译.需要更新(
                to: latest,
                installedRevision: "aaaa",
                downloadedAt: downloadedAt
            )
        )
        #expect(
            VNDB简介人工翻译.需要更新(
                to: latest,
                installedRevision: nil,
                downloadedAt: downloadedAt
            )
        )
        #expect(
            !VNDB简介人工翻译.需要更新(
                to: latest,
                installedRevision: nil,
                downloadedAt: Date(timeIntervalSince1970: 3_000)
            )
        )
    }

    @Test
    func 更新提示以MB显示文件大小() {
        let update = VNDB简介翻译版本(
            revision: "bbbb",
            committedAt: nil,
            archiveBytes: 18_382_602
        )
        #expect(update.archiveSizeText.contains("18"))
        #expect(update.archiveSizeText.contains("MB"))
    }

    private func 写入空压缩包(comment: String) throws -> URL {
        let commentData = Data(comment.utf8)
        var data = Data([0x50, 0x4B, 0x05, 0x06])
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        data.append(UInt8(commentData.count & 0xFF))
        data.append(UInt8(commentData.count >> 8))
        data.append(commentData)

        let url = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString).zip",
            directoryHint: .notDirectory
        )
        try data.write(to: url)
        return url
    }
}
