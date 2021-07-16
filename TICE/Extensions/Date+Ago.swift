//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

public extension Date {

    private var calendar: Calendar { return .current }

    private var components: DateComponents {
        let unitFlags = Set<Calendar.Component>([.second, .minute, .hour, .day, .weekOfYear, .month, .year])
        let now = Date()
        return calendar.dateComponents(unitFlags, from: self, to: now)
    }

    func timeAgo(numericDates: Bool = false, minSeconds: Int = 3) -> String {
        if let year = components.year, year > 0 {
            if year >= 2 { return L10n.TimeAgo.Year.mutiple("\(year)") }
            return LocalizedString(numericDates ? "timeAgo_year_one" : "timeAgo_year_last")
        } else if let month = components.month, month > 0 {
            if month >= 2 { return L10n.TimeAgo.Month.mutiple("\(month)") }
            return LocalizedString(numericDates ? "timeAgo_month_one" : "timeAgo_month_last")
        } else if let week = components.weekOfYear, week > 0 {
            if week >= 2 { return L10n.TimeAgo.Week.mutiple("\(week)") }
            return LocalizedString(numericDates ? "timeAgo_week_one" : "timeAgo_week_last")
        } else if let day = components.day, day > 0 {
            let isYesterday = calendar.isDateInYesterday(self)
            if day >= 2 && !isYesterday { return L10n.TimeAgo.Day.mutiple("\(day)") }
            return LocalizedString(numericDates ? "timeAgo_day_one" : "timeAgo_day_last")
        } else if let hour = components.hour, hour > 0 {
            if hour >= 2 { return L10n.TimeAgo.Hour.mutiple("\(hour)") }
            return LocalizedString(numericDates ? "timeAgo_hour_one" : "timeAgo_hour_last")
        } else if let minute = components.minute, minute > 0 {
            if minute >= 2 { return L10n.TimeAgo.Minute.mutiple("\(minute)") }
            return LocalizedString(numericDates ? "timeAgo_minute_one" : "timeAgo_minute_last")
        } else if let second = components.second {
            if second >= 2 { return second >= minSeconds ? L10n.TimeAgo.Second.mutiple("\(second)") : L10n.TimeAgo.Second.last }
            return second >= minSeconds ? L10n.TimeAgo.Second.one : L10n.TimeAgo.Second.last
        }
        return L10n.TimeAgo.Second.last
    }

    func shortTimeAgo() -> String {
        if let year = components.year, year > 0 {
            return L10n.TimeAgo.Year.short("\(year)")
        } else if let month = components.month, month > 0 {
            return L10n.TimeAgo.Month.short("\(month)")
        } else if let week = components.weekOfYear, week > 0 {
            return L10n.TimeAgo.Week.short("\(week)")
        } else if let day = components.day, day > 0 {
            if calendar.isDateInYesterday(self) { return L10n.TimeAgo.Day.Short.yesterday }
            return L10n.TimeAgo.Day.short("\(day)")
        } else if let hour = components.hour, hour > 0 {
            return L10n.TimeAgo.Hour.short("\(hour)")
        } else if let minute = components.minute, minute > 0 {
            return L10n.TimeAgo.Minute.short("\(minute)")
        } else if let second = components.second, second > 0 {
            return L10n.TimeAgo.Second.short("\(second)")
        }
        return L10n.TimeAgo.Short.default
    }

}
