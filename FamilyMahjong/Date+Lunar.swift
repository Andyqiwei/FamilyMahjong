//
//  Date+Lunar.swift
//  FamilyMahjong
//
//  农历日期格式化：大年三十至正月十五返回农历中文字符串，否则返回阳历。
//

import Foundation

extension Date {

    /// 农历日期格式化：若是大年三十至正月十五，返回对应农历中文字符串；否则返回阳历如 "2月14日"。
    func festiveDateString() -> String {
        let chinese = Calendar(identifier: .chinese)
        let lunar = chinese.dateComponents([.month, .day], from: self)
        guard let m = lunar.month, let d = lunar.day else { return solarDateString() }

        // 腊月三十
        if m == 12 && d == 30 { return "大年三十" }
        // 腊月廿九
        if m == 12 && d == 29 { return "腊月廿九" }
        // 正月初一 ~ 正月十五
        if m == 1 && d >= 1 && d <= 15 {
            let dayNames = ["", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十", "十一", "十二", "十三", "十四", "十五"]
            return d <= 10 ? "大年" + dayNames[d] : "正月" + dayNames[d]
        }

        return solarDateString()
    }

    private func solarDateString() -> String {
        let cal = Calendar.current
        let m = cal.component(.month, from: self)
        let d = cal.component(.day, from: self)
        return "\(m)月\(d)日"
    }
}
