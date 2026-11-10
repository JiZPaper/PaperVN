import UIKit
import QuartzCore

enum DBG边缘效果 {
    static var 已启动 = false
    static func 启动() {
        guard !已启动 else { return }
        已启动 = true
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { 打印() }
        }
    }

    static func 描述(_ l: CALayer, _ d: Int, _ out: inout [String]) {
        let pad = String(repeating: "  ", count: d)
        var line = "\(pad)L \(type(of: l)) f=\(l.frame.integral) op=\(l.opacity) hid=\(l.isHidden)"
        if let bg = l.backgroundColor { line += " bg=\(UIColor(cgColor: bg))" }
        if let fs = l.filters, !fs.isEmpty { line += " filters=\(fs)" }
        if let bf = l.backgroundFilters, !bf.isEmpty { line += " bgFilters=\(bf)" }
        if let cf = l.compositingFilter { line += " comp=\(cf)" }
        if l.contents != nil { line += " contents=\(String(describing: l.contents.map { CFGetTypeID($0 as CFTypeRef) }))" }
        if let g = l as? CAGradientLayer {
            line += " grad colors=\(g.colors ?? []) loc=\(g.locations ?? []) s=\(g.startPoint) e=\(g.endPoint) type=\(g.type)"
        }
        // 私有属性
        for key in ["scale", "groupName", "captureOnly", "zoom", "allowsInPlaceFiltering", "marginWidth"] {
            if l.responds(to: NSSelectorFromString(key)), let v = l.value(forKey: key) { line += " \(key)=\(v)" }
        }
        out.append(line)
        if let m = l.mask {
            out.append("\(pad)  MASK:")
            描述(m, d + 2, &out)
        }
        for sub in l.sublayers ?? [] { 描述(sub, d + 1, &out) }
    }

    static func 打印() {
        guard let win = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        var out: [String] = []
        func walk(_ v: UIView) {
            let n = String(describing: type(of: v))
            if n == "ScrollEdgeEffectView" {
                let f = v.convert(v.bounds, to: win).integral
                var chain: [String] = []
                var p = v.superview
                for _ in 0..<8 { if let q = p { chain.append(String(describing: type(of: q))); p = q.superview } }
                out.append("== \(n) win=\(f) alpha=\(v.alpha) hidden=\(v.isHidden)")
                out.append("   chain: " + chain.joined(separator: " < "))
                func sub(_ x: UIView, _ d: Int) {
                    let pad = String(repeating: "  ", count: d)
                    out.append("\(pad)V \(type(of: x)) f=\(x.frame.integral) a=\(x.alpha) h=\(x.isHidden) bg=\(String(describing: x.backgroundColor))")
                    描述(x.layer, d + 1, &out)
                    x.subviews.forEach { sub($0, d + 1) }
                }
                sub(v, 1)
                return
            }
            v.subviews.forEach(walk)
        }
        walk(win)
        print("DBGPOCKET BEGIN\n" + out.joined(separator: "\n") + "\nDBGPOCKET END")
    }
}
