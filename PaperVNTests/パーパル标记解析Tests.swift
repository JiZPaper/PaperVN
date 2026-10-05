import Foundation
import Testing

@testable import PaperVN

@Suite("パーパル标记解析")
struct パーパル标记解析Tests {
  @Test("作品标记转成卡片并从正文里移除标记语法")
  func 解析视觉小说标记() {
    let 结果 = パーパル标记解析.解析(
      "这部大概是[[VN|v17|Ever17 -the out of infinity-]]にゃ～"
    )

    #expect(结果.显示文本 == "这部大概是Ever17 -the out of infinity-にゃ～")
    #expect(结果.卡片.count == 1)
    #expect(结果.卡片.first?.类型 == .visualNovel)
    #expect(结果.卡片.first?.vndbID == "v17")
    #expect(结果.卡片.first?.名称 == "Ever17 -the out of infinity-")
  }

  @Test("角色标记与纯数字编号都能补上前缀")
  func 解析角色标记() {
    let 结果 = パーパル标记解析.解析("[[CHAR|46|优希堂悠]]")

    #expect(结果.显示文本 == "优希堂悠")
    #expect(结果.卡片.first?.类型 == .character)
    #expect(结果.卡片.first?.vndbID == "c46")
  }

  @Test("占位编号视为未知，交给按名称检索")
  func 未知编号() {
    let 结果 = パーパル标记解析.解析("[[VN|-|ものべの]]和[[VN|?|素晴らしき日々]]")

    #expect(结果.卡片.count == 2)
    #expect(结果.卡片.allSatisfy { $0.vndbID == nil })
    #expect(结果.显示文本 == "ものべの和素晴らしき日々")
  }

  @Test("省略编号的两段式标记也接受")
  func 省略编号() {
    let 结果 = パーパル标记解析.解析("[[VN|CLANNAD]]")

    #expect(结果.卡片.first?.vndbID == nil)
    #expect(结果.卡片.first?.名称 == "CLANNAD")
    #expect(结果.显示文本 == "CLANNAD")
  }

  @Test("重复的卡片只保留一张")
  func 卡片去重() {
    let 结果 = パーパル标记解析.解析(
      "[[VN|v17|Ever17]]……还是[[VN|v17|Ever17]]"
    )

    #expect(结果.卡片.count == 1)
  }

  @Test("网络引用保留正文标准编号并把链接集中到下方")
  func 网络引用() {
    let 结果 = パーパル标记解析.解析(
      "根据资料[[1]](https://example.com/one)可知，另见[2](https://example.com/two)。"
    )

    #expect(结果.显示文本 == "根据资料[1]可知，另见[2]。")
    #expect(结果.引用.map(\.显示文本) == ["example.com", "example.com"])
    #expect(结果.引用.map(\.行内标记) == ["[1]", "[2]"])
    #expect(结果.引用.map(\.地址.absoluteString) == [
      "https://example.com/one",
      "https://example.com/two"
    ])
  }

  @Test("历史消息中的旧引用标记会迁移为标准编号")
  func 迁移旧引用标记() throws {
    let 引用 = パーパル网络引用(
      编号: "1",
      地址: URL(string: "https://example.com/article")!
    )
    let 消息 = パーパル消息(
      角色: .assistant,
      文本: "旧格式⁽¹⁾、半角(1)、全角（1）",
      引用: [引用]
    )
    let 编码器 = JSONEncoder()
    let 解码器 = JSONDecoder()
    let 迁移后 = try 解码器.decode(
      パーパル消息.self,
      from: 编码器.encode(消息)
    )

    #expect(迁移后.文本 == "旧格式[1]、半角[1]、全角[1]")
  }

  @Test("来源胶囊使用网站名称并限制最大长度")
  func 来源名称截断() {
    let 长主机 = String(repeating: "very-long-source-", count: 4) + "example.com"
    let 结果 = パーパル标记解析.解析(
      "资料[1](https://\(长主机)/article)"
    )

    let 名称 = try! #require(结果.引用.first?.显示文本)
    #expect(名称.count == パーパル额度.来源名称字数上限)
    #expect(名称.hasSuffix("…"))
    #expect(结果.引用.first?.图标地址?.absoluteString == "https://\(长主机)/favicon.ico")
  }

  @Test("流式输出时写了一半的标记先隐藏")
  func 流式隐藏未闭合标记() {
    let 流式 = パーパル标记解析.解析("推荐这部[[VN|v17|Ever", 流式: true)
    #expect(流式.显示文本 == "推荐这部")
    #expect(流式.卡片.isEmpty)

    let 完成 = パーパル标记解析.解析("推荐这部[[VN|v17|Ever")
    #expect(完成.显示文本 == "推荐这部[[VN|v17|Ever")
  }

  @Test("无法识别的标记原样保留")
  func 保留未知标记() {
    let 结果 = パーパル标记解析.解析("[[UNKNOWN|内容]]")

    #expect(结果.显示文本 == "[[UNKNOWN|内容]]")
    #expect(结果.卡片.isEmpty)
  }

  @Test("标记内换行视为写坏了，回退成正文")
  func 标记内换行() {
    let 结果 = パーパル标记解析.解析("[[VN|v17|Ever\n17]]")

    #expect(结果.卡片.isEmpty)
    #expect(结果.显示文本.contains("[[VN|v17|Ever"))
  }

  @Test("移除标记后不留多余空行与行尾空格")
  func 规范化空白() {
    let 结果 = パーパル标记解析.解析(
      """
      第一行
      [[TITLE|某个事实]]

      \u{20}
      第二行
      """
    )

    #expect(结果.显示文本 == "第一行\n\n第二行")
  }

  @Test("不带标记的普通回复原样通过")
  func 无标记回复() {
    let 结果 = パーパル标记解析.解析("这个话题Paparu不能回答にゃ……")

    #expect(结果.显示文本 == "这个话题Paparu不能回答にゃ……")
    #expect(结果.卡片.isEmpty)
    #expect(结果.标题 == nil)
  }

  @Test("记忆标记从正文隐藏并被解析为跨对话摘要")
  func 解析记忆标记() {
    let 结果 = パーパル标记解析.解析("[[MEMORY|用户曾和Paparu讨论过Ever17的叙事结构。]]")

    #expect(结果.显示文本.isEmpty)
    #expect(结果.卡片.isEmpty)
    #expect(结果.记忆摘要 == "用户曾和Paparu讨论过Ever17的叙事结构。")
  }

  @Test("多个记忆标记以最后一份摘要为准并限制摘要长度")
  func 记忆标记边界() {
    let 最后摘要 = String(repeating: "摘要", count: 1_100)
    let 原文 = "[[MEMORY|旧摘要|第一版]][[MEMORY|上下文|第二版]][[MEMORY|\(最后摘要)]]"
    let 结果 = パーパル标记解析.解析(原文)

    #expect(结果.显示文本.isEmpty)
    #expect(结果.记忆摘要?.count == パーパル额度.记忆字数上限)
    #expect(结果.记忆摘要?.hasPrefix("摘要摘要") == true)
  }

  @Test("记忆功能没有旧设置时默认开启")
  func 记忆功能默认开启() {
    let defaults = UserDefaults(suiteName: "PaperVN.MemoryDefaultTests.\(UUID().uuidString)")!
    #expect(パーパル偏好.读取记忆功能(defaults: defaults))
    #expect(defaults.bool(forKey: パーパル偏好.记忆功能键))
  }

  @Test("标题标记不出现在正文里")
  func 解析标题标记() {
    let 结果 = パーパル标记解析.解析(
      """
      找到了にゃ～
      [[TITLE|孤岛失忆题材的作品]]
      """
    )

    #expect(结果.显示文本 == "找到了にゃ～")
    #expect(结果.标题 == "孤岛失忆题材的作品")
  }

  @Test("多个标题标记以最后一个为准，并按字数上限截断")
  func 标题去重与截断() {
    let 长标题 = String(repeating: "标", count: 80)
    let 结果 = パーパル标记解析.解析(
      "[[TITLE|旧标题]]好にゃ[[TITLE|\(长标题)]]"
    )

    #expect(结果.显示文本 == "好にゃ")
    #expect(结果.标题?.count == パーパル额度.标题字数上限)
  }
}

@Suite("パーパル模型配置")
struct パーパル模型配置Tests {
  @Test("动态配置JSON可以解析并保留Responses地址")
  func 动态配置解码() throws {
    let 数据 = Data(
      "{\"schemaVersion\":1,\"baseURL\":\"https://example.com/v1\",\"apiKey\":\" test-key \"}".utf8
    )

    let 配置 = try JSONDecoder().decode(
      パーパル模型配置值.self,
      from: 数据
    )

    #expect(配置.基础地址 == "https://example.com/v1")
    #expect(配置.API密钥 == "test-key")
    #expect(
      パーパル模型配置.响应地址(基础: 配置.基础地址)?.absoluteString
        == "https://example.com/v1/responses"
    )
  }

  @Test("动态配置拒绝非HTTPS地址和带查询参数的地址")
  func 动态配置地址校验() {
    #expect(パーパル模型配置.响应地址(基础: "http://example.com") == nil)
    #expect(パーパル模型配置.响应地址(基础: "https://example.com?v=1") == nil)
    let 空密钥配置 = try? パーパル模型配置值(
      基础地址: "https://example.com",
      API密钥: ""
    )
    #expect(空密钥配置 == nil)
  }

  @Test("基础地址补全成Responses端点")
  func 响应地址补全() {
    #expect(
      パーパル模型配置.响应地址(基础: "https://yh.shiyi11.xyz")?.absoluteString
        == "https://yh.shiyi11.xyz/v1/responses"
    )
    #expect(
      パーパル模型配置.响应地址(基础: "https://yh.shiyi11.xyz/")?.absoluteString
        == "https://yh.shiyi11.xyz/v1/responses"
    )
    #expect(
      パーパル模型配置.响应地址(基础: "https://yh.shiyi11.xyz/v1")?.absoluteString
        == "https://yh.shiyi11.xyz/v1/responses"
    )
    #expect(
      パーパル模型配置.响应地址(
        基础: "https://yh.shiyi11.xyz/v1/chat/completions"
      )?.absoluteString == "https://yh.shiyi11.xyz/v1/responses"
    )
    #expect(
      パーパル模型配置.响应地址(
        基础: "https://yh.shiyi11.xyz/v1/responses"
      )?.absoluteString == "https://yh.shiyi11.xyz/v1/responses"
    )
    #expect(パーパル模型配置.响应地址(基础: "  ") == nil)
  }

  @Test("错误类型映射为用户可见文案")
  func 用户错误文案() {
    #expect(
      パーパル服务错误.用户错误文案(URLError(.notConnectedToInternet))
        == "网络不可用。"
    )
    #expect(
      パーパル服务错误.用户错误文案(URLError(.timedOut))
        == "请求已超时。"
    )
    #expect(
      パーパル服务错误.用户错误文案(パーパル服务错误.无效地址)
        == "当前Paparu不可用。"
    )
    #expect(
      パーパル服务错误.用户错误文案(パーパル服务错误.响应异常)
        == "Paparu遇到未知错误。"
    )
  }
}

@Suite("パーパル回答版本")
struct パーパル回答版本Tests {
  @Test("重新生成的回答可以保存并切换")
  func 回答版本() {
    var 消息 = パーパル消息(角色: .assistant, 文本: "第一份回答")
    消息.收录当前回答()
    消息.文本 = "第二份回答"
    消息.收录当前回答()

    #expect(消息.回答总数 == 2)
    #expect(消息.当前回答索引 == 1)
    消息.当前回答索引 = 0
    消息.恢复当前回答()
    #expect(消息.文本 == "第一份回答")
  }
}

@Suite("パーパル会话标题")
struct パーパル会话标题Tests {
  @Test("没有标题时显示“新对话”")
  func 默认标题() {
    #expect(パーパル会话().显示标题 == String(localized: "新对话"))
    #expect(
      パーパル会话(标题: "   ").显示标题 == String(localized: "新对话")
    )
  }

  @Test("模型设置的标题优先显示")
  func 模型设置标题() {
    #expect(パーパル会话(标题: "孤岛失忆题材").显示标题 == "孤岛失忆题材")
  }
}

@Suite("パーパル会话额度")
struct パーパル会话额度Tests {
  @Test("额度只统计用户发出的消息")
  func 用户消息计数() {
    var 会话 = パーパル会话()
    会话.消息 = [
      パーパル消息(角色: .user, 文本: "一"),
      パーパル消息(角色: .assistant, 文本: "回复一"),
      パーパル消息(角色: .user, 文本: "二"),
      パーパル消息(角色: .assistant, 文本: "回复二")
    ]

    #expect(会话.用户消息数 == 2)
    #expect(会话.剩余消息数 == パーパル额度.单会话用户消息上限 - 2)
    #expect(!会话.已用尽额度)
  }

  @Test("发满上限后额度用尽")
  func 额度用尽() {
    var 会话 = パーパル会话()
    会话.消息 = (1...パーパル额度.单会话用户消息上限).map {
      パーパル消息(角色: .user, 文本: "第\($0)条")
    }

    #expect(会话.剩余消息数 == 0)
    #expect(会话.已用尽额度)
  }
}
