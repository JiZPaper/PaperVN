import Foundation

/// AniList 的类型与标签以及 MAL 的类型：显示名称来自 `AniListTags.xcstrings`（中、日、韩、德、波兰文），筛选用的目录来自 AniList 的 MediaTagCollection（不含成人标签）。
nonisolated enum AniList标签 {
    /// 动画、漫画与轻小说详情页和筛选里显示的名称；表里没有的保持原文。
    static func 显示名称(_ name: String) -> String {
        // MAL 的“Boys Love”与 AniList 的“Boys' Love”在表里共用一条（两个键会生成同名符号）
        let key = name == "Boys Love" ? "Boys' Love" : name
        return String(localized: String.LocalizationValue(key), table: "AniListTags")
    }

    static func 分类名称(_ category: String) -> String {
        switch category {
        case "Theme": String(localized: "主题")
        case "Setting": String(localized: "舞台")
        case "Cast": String(localized: "角色")
        case "Demographic": String(localized: "受众")
        case "Technical": String(localized: "技术")
        case "Sexual Content": String(localized: "色情")
        default: category
        }
    }

    /// 按分类排好的标签（AniList 原名）。
    static let 目录: [(分类: String, 标签: [String])] = [
        ("Theme", ["Acrobatics", "Acting", "Adoption", "Age Gap", "Agriculture", "Airsoft", "Alchemy", "American Football", "Animals", "Archery", "Assassins", "Astronomy", "Athletics", "Autobiographical", "Aviation", "Badminton", "Ballet", "Band", "Baseball", "Basketball", "Battle Royale", "Biographical", "Blackmail", "Board Game", "Body Horror", "Body Image", "Body Swapping", "Bowling", "Boxing", "Boys' Love", "Brainwashing", "Bullying", "Calligraphy", "Cannibalism", "Card Battle", "Cars", "Cheating", "Cheerleading", "Chibi", "Class Struggle", "Classic Literature", "Classical Music", "Cohabitation", "Coming of Age", "Conspiracy", "Cosmic Horror", "Creature Taming", "Crime", "Criminal Organization", "Crossover", "Cult", "Cultivation", "Curses", "Cute Boys Doing Cute Things", "Cute Girls Doing Cute Things", "Cyberpunk", "Cycling", "Dancing", "Death Game", "Denpa", "Drawing", "Drugs", "E-Sports", "Eco-Horror", "Economics", "Educational", "Environmental", "Ero Guro", "Espionage", "Exiled", "Exorcism", "Fairy Tale", "Fake Relationship", "Family Life", "Fashion", "Female Harem", "Fencing", "Filmmaking", "Firefighters", "Fishing", "Fitness", "Food", "Football", "Found Family", "Fugitive", "Gambling", "Gangs", "Gender Bending", "Go", "Golf", "Gore", "Guns", "Handball", "Henshin", "Heterosexual", "Hip-hop Music", "Horticulture", "Human Experimentation", "Ice Sports", "Incest", "Indigenous Cultures", "Inseki", "Interspecies", "Isekai", "Iyashikei", "Jazz Music", "Judo", "Kabuki", "Kaiju", "Karuta", "Kingdom Management", "Lacrosse", "Language Barrier", "LGBTQ+ Themes", "Lost Civilization", "Love Triangle", "Mafia", "Magic", "Mahjong", "Makeup", "Male Harem", "Manzai", "Marriage", "Martial Arts", "Matchmaking", "Matriarchy", "Medicine", "Memory Manipulation", "Meta", "Metal Music", "Military", "Mixed Gender Harem", "Modeling", "Mopeds", "Motorcycles", "Mountaineering", "Musical Theater", "Mythology", "Necromancy", "Noir", "Otaku Culture", "Pandemic", "Parenthood", "Parkour", "Parody", "Philosophy", "Photography", "Poker", "Police", "Politics", "Polyamorous", "Pregnancy", "Prophecy", "Proxy Battle", "Psychosexual", "Rakugo", "Real Robot", "Rehabilitation", "Reincarnation", "Religion", "Rescue", "Revenge", "Reverse Isekai", "Rock Music", "Royal Affairs", "Rugby", "Satire", "Scuba Diving", "Shapeshifting", "Ships", "Shogi", "Skateboarding", "Slapstick", "Slavery", "Software Development", "Space Opera", "Spearplay", "Steampunk", "Suicide", "Sumo", "Super Power", "Super Robot", "Superhero", "Surfing", "Surreal Comedy", "Survival", "Swimming", "Swordplay", "Table Tennis", "Tanks", "Teens' Love", "Tennis", "Terrorism", "Time Loop", "Time Manipulation", "Tokusatsu", "Torture", "Tragedy", "Trains", "Travel", "Triads", "Unrequited Love", "Video Games", "Vocal Synth", "Volleyball", "War", "Wrestling", "Writing", "Wuxia", "Yakuza", "Youkai", "Yuri"]),
        ("Setting", ["Achronological Order", "Afterlife", "Alternate Universe", "Anachronism", "Ancient China", "Augmented Reality", "Bar", "Boarding School", "Camping", "Circus", "Coastal", "College", "Desert", "Dungeon", "Dystopian", "Foreign", "Historical", "Inn", "Konbini", "Medieval", "Middle East", "Natural Disaster", "Office", "Outdoor Activities", "Post-Apocalyptic", "Prison", "Restaurant", "Rural", "School", "School Club", "Snowscape", "Space", "Time Skip", "Urban", "Urban Fantasy", "Virtual World", "Wilderness", "Work"]),
        ("Cast", ["Age Regression", "Agender", "Aliens", "Amnesia", "Angels", "Anthropomorphism", "Anti-Hero", "Aromantic", "Arranged Marriage", "Artificial Intelligence", "Asexual", "Bisexual", "Butler", "Centaur", "Chimera", "Chuunibyou", "Clone", "Cosplay", "Cowboys", "Crossdressing", "Cyborg", "Delinquents", "Demons", "Detective", "Dinosaurs", "Disability", "Dissociative Identities", "Dragons", "Dullahan", "Elderly Protagonist", "Elf", "Ensemble Cast", "Estranged Family", "Fairy", "Female Protagonist", "Femboy", "Ghost", "Goblin", "Gods", "Gyaru", "Hikikomori", "Homeless", "Idol", "Kemonomimi", "Kuudere", "Maids", "Male Protagonist", "Mermaid", "Monster Boy", "Monster Girl", "Nekomimi", "Ninja", "Nudity", "Nun", "Office Lady", "Oiran", "Ojou-sama", "Orphan", "Pirates", "Primarily Adult Cast", "Primarily Animal Cast", "Primarily Child Cast", "Primarily Female Cast", "Primarily Male Cast", "Primarily Teen Cast", "Robots", "Samurai", "Shrine Maiden", "Skeleton", "Succubus", "Tanned Skin", "Teacher", "Tomboy", "Transgender", "Tsundere", "Twins", "Vampire", "Veterinarian", "Vikings", "Villainess", "VTuber", "Werewolf", "Witch", "Yandere", "Zombie"]),
        ("Demographic", ["Josei", "Kids", "Seinen", "Shoujo", "Shounen"]),
        ("Technical", ["4-koma", "Achromatic", "Advertisement", "Anthology", "CGI", "Episodic", "Flash", "Full CGI", "Full Color", "Gekiga", "Graduation Project", "Long Strip", "Mixed Media", "No Dialogue", "Non-fiction", "POV", "Puppetry", "Rotoscoping", "Short-Form Chapter", "Stop Motion", "Vertical Video"]),
    ]
}

/// AniList 制作人员的职位，例如“Episode Director (eps 1, 3)”：职位名来自 `AniListStaffRoles.xcstrings`，括号里的集数、片头曲、语言等另外翻译。
nonisolated enum AniList职位 {
    /// 拆成职位和括号里的备注。
    static func 拆分(_ role: String) -> (职位: String, 备注: String?) {
        guard role.hasSuffix(")"), let open = role.firstIndex(of: "(") else {
            return (role.trimmingCharacters(in: .whitespaces), nil)
        }
        let base = role[..<open].trimmingCharacters(in: .whitespaces)
        let note = role[role.index(after: open)..<role.index(before: role.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? role : base, note.isEmpty ? nil : note)
    }

    /// 表里没有的职位保持原文。AniList 偶尔有大小写不同的写法（“Animation producer”），再按每个单词首字母大写查一次。
    static func 显示名称(_ role: String) -> String {
        let localized = String(localized: String.LocalizationValue(role), table: "AniListStaffRoles")
        guard localized == role else { return localized }
        let titled = role.capitalized(with: Locale(identifier: "en"))
        guard titled != role else { return role }
        let retried = String(localized: String.LocalizationValue(titled), table: "AniListStaffRoles")
        return retried == titled ? role : retried
    }

    /// 按 App 的界面语言判断，不看 `Locale.current`（那是地区格式，界面是中文时地区可能是美国）。
    private static var 界面语言: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "zh-Hans")
    }

    static var 使用中日文标点: Bool {
        ["zh", "ja"].contains(界面语言.language.languageCode?.identifier ?? "")
    }

    /// 职位连同括号里的备注一起翻译，用在人物详情的作品卡片上（“导演（第1–3话）”）。
    static func 完整显示名称(_ role: String) -> String {
        let (base, note) = 拆分(role)
        let name = 显示名称(base)
        guard let note else { return name }
        return 使用中日文标点 ? "\(name)（\(备注(note))）" : "\(name) (\(备注(note)))"
    }

    /// “eps 1-3”“OP2”“English: vols 1-3”“former”等翻译成界面语言。
    static func 备注(_ note: String) -> String {
        let cjk = 使用中日文标点
        func 范围(_ value: Substring) -> String {
            var text = value.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
            text = text.replacingOccurrences(of: "-", with: "–")
            if cjk { text = text.replacingOccurrences(of: ", ", with: "、") }
            return text.replacingOccurrences(of: " ", with: "")
        }
        var text = note
        text = text.replacing(/\b[Ee]ps?\.?\s*(\d[\d,\s\-–]*)/) { match in
            String(localized: "第\(范围(match.1))话")
        }
        text = text.replacing(/\b[Vv]ols?\.?\s*(\d[\d,\s\-–]*)/) { match in
            String(localized: "第\(范围(match.1))卷")
        }
        text = text.replacing(/\b[Cc]hs?\.?\s*(\d[\d,\s\-–]*)/) { match in
            String(localized: "第\(范围(match.1))章")
        }
        text = text.replacing(/\bOP\s*(\d*)\b/) { match in
            match.1.isEmpty ? String(localized: "片头曲") : String(localized: "片头曲\(String(match.1))")
        }
        text = text.replacing(/\bED\s*(\d*)\b/) { match in
            match.1.isEmpty ? String(localized: "片尾曲") : String(localized: "片尾曲\(String(match.1))")
        }
        text = text.replacing(/\b[Ff]ormer\b/) { _ in String(localized: "前任") }
        text = text.replacing(/\b[A-Z][a-z]+\b/) { match in
            语言名称[String(match.0)] ?? String(match.0)
        }
        if cjk {
            text = text.replacingOccurrences(of: ": ", with: "：")
                .replacingOccurrences(of: ":", with: "：")
                .replacingOccurrences(of: ", ", with: "，")
        }
        return text
    }

    /// 英文语言名（“English”“Portuguese”）→ 界面语言的名称。
    private static let 语言名称: [String: String] = {
        let english = Locale(identifier: "en")
        var names: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes where code.identifier.count == 2 {
            guard let name = english.localizedString(forLanguageCode: code.identifier),
                  let localized = 界面语言.localizedString(forLanguageCode: code.identifier) else { continue }
            names[name] = localized
        }
        return names
    }()

    /// 与视觉小说详情的制作人员图标一致。
    static func 图标(_ role: String) -> String {
        let r = role.lowercased()
        if r.contains("song") { return "music.microphone" }
        if r.contains("music") { return "music.quarternote.3" }
        if r.contains("sound") || r.contains("adr") || r.contains("recording") || r.contains("mix") { return "speaker.wave.2" }
        if r.contains("director"), !r.contains("animation"), !r.contains("art"), !r.contains("photography") { return "megaphone" }
        if r.contains("design") { return "paintbrush" }
        if r.contains("animat") || r.contains("art") || r.contains("illustration") || r.contains("storyboard") { return "pencil.and.outline" }
        if r.contains("story") || r.contains("script") || r.contains("composition") || r.contains("original") || r.contains("literary") { return "text.book.closed" }
        if r.contains("translat") || r.contains("letter") { return "character.bubble" }
        if r.contains("edit") { return "scissors" }
        if r.contains("photography") || r.contains("cg") || r.contains("effects") || r.contains("2d") || r.contains("3d") { return "camera.aperture" }
        if r.contains("produc") || r.contains("planning") || r.contains("desk") { return "wrench.and.screwdriver" }
        return "person.2"
    }
}
