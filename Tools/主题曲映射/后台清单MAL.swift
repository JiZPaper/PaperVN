// 后台清单用：读 MAL 主题曲缓存（训练数据/主题曲匹配/MAL主题曲.jsonl，每行 {"path","body"}），
// 用 App 的 动画主题曲 解析每首片头曲、片尾曲，输出 JSON Lines（生成后台清单.py 读取）。
// 编译：swiftc -O -o <输出> Tools/主题曲映射/后台清单MAL.swift PaperVN/非用户界面/资料库/动画主题曲.swift
import Foundation
struct 行: Decodable { let path: String; let body: 作品 }
struct 作品: Decodable { let id: Int; let title: String?; let alternative_titles: 别名?; let opening_themes: [主题]?; let ending_themes: [主题]? }
struct 别名: Decodable { let ja: String? }
struct 主题: Decodable { let id: Int; let text: String }
let input = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var latest: [Int: 作品] = [:]
for line in input.split(separator: "\n") {
    guard let row = try? JSONDecoder().decode(行.self, from: Data(line.utf8)), row.path.contains("opening_themes") else { continue }
    latest[row.body.id] = row.body
}
var out = ""
for (malID, work) in latest {
    let anime = work.alternative_titles?.ja.flatMap { $0.isEmpty ? nil : $0 } ?? work.title
    for (themes, kind) in [(work.opening_themes ?? [], 动画主题曲.种类.片头曲), (work.ending_themes ?? [], 动画主题曲.种类.片尾曲)] {
        for theme in themes {
            guard let song = 动画主题曲(malID: theme.id, 种类: kind, 文本: theme.text) else { continue }
            let item: [String: Any?] = ["key": String(theme.id), "malID": malID, "anime": anime, "kind": kind == .片头曲 ? "op" : "ed",
                "number": song.序号, "title": song.标题, "originalTitle": song.原标题, "artist": song.歌手, "originalArtist": song.歌手原名,
                "episodes": song.话数, "text": theme.text]
            let data = try JSONSerialization.data(withJSONObject: item.compactMapValues { $0 }, options: [.withoutEscapingSlashes])
            out += String(data: data, encoding: .utf8)! + "\n"
        }
    }
}
try out.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print(latest.count, "部作品")
