import SwiftUI

struct ToastStyle {
    var showFromKey: Bool = true
    var showArrow: Bool = true
    var showToKey: Bool = true
    var showNote: Bool = true
    var displayDuration: Double = 2.0
    var fadeOutDuration: Double = 0.5
    var fontSize: CGFloat = 14
    var textColor: Color = .white
    var bgColor: Color = Color.black.opacity(0.75)
    var cornerRadius: CGFloat = 8

    func loadFromDefaults() -> ToastStyle {
        var s = self
        let d = UserDefaults.standard
        s.showFromKey = d.bool(forKey: "toast_show_from_key")
        s.showArrow = d.bool(forKey: "toast_show_arrow")
        s.showToKey = d.bool(forKey: "toast_show_to_key")
        s.showNote = d.bool(forKey: "toast_show_note")
        s.displayDuration = d.double(forKey: "toast_display_duration")
        s.fadeOutDuration = d.double(forKey: "toast_fade_out_duration")
        s.fontSize = CGFloat(d.double(forKey: "toast_font_size"))
        s.cornerRadius = CGFloat(d.double(forKey: "toast_corner_radius"))
        if let data = d.data(forKey: "toast_text_color"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            s.textColor = Color(nsColor: c)
        }
        if let data = d.data(forKey: "toast_bg_color"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            s.bgColor = Color(nsColor: c)
        }
        if s.displayDuration == 0 { s.displayDuration = 2.0 }
        if s.fadeOutDuration == 0 { s.fadeOutDuration = 0.5 }
        if s.fontSize == 0 { s.fontSize = 14 }
        return s
    }

    func saveToDefaults() {
        let d = UserDefaults.standard
        d.set(showFromKey, forKey: "toast_show_from_key")
        d.set(showArrow, forKey: "toast_show_arrow")
        d.set(showToKey, forKey: "toast_show_to_key")
        d.set(showNote, forKey: "toast_show_note")
        d.set(displayDuration, forKey: "toast_display_duration")
        d.set(fadeOutDuration, forKey: "toast_fade_out_duration")
        d.set(Double(fontSize), forKey: "toast_font_size")
        d.set(Double(cornerRadius), forKey: "toast_corner_radius")
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(textColor), requiringSecureCoding: false) {
            d.set(data, forKey: "toast_text_color")
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(bgColor), requiringSecureCoding: false) {
            d.set(data, forKey: "toast_bg_color")
        }
    }

    func assembleText(fromName: String, toName: String, note: String) -> String {
        var parts: [String] = []
        if showFromKey { parts.append(fromName) }
        if showArrow { parts.append("->") }
        if showToKey { parts.append(toName) }
        if showNote && !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " ")
    }
}
