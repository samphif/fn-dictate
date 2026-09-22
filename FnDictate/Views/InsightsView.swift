import AppKit
import SwiftUI

struct InsightsView: View {
    let insights: UsageInsights

    @State private var tab: InsightsTab = .usage
    @State private var monthOffset = 0

    private enum InsightsTab: String, CaseIterable, Identifiable {
        case usage = "Your usage"
        case voice = "Your voice"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Insights")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .padding(.top, 8)

                tabBar

                switch tab {
                case .usage:
                    usagePane
                case .voice:
                    voicePane
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(InsightsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? FlowTheme.ink : FlowTheme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == item ? FlowTheme.ink : Color.clear)
                                .frame(height: 2)
                                .offset(y: 8)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var usagePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                dictationsCard
                fixesCard
                wordsCard
            }

            HStack(alignment: .top, spacing: 14) {
                desktopUsageCard
                    .frame(minWidth: 380, maxWidth: .infinity)
                streakCard
                    .frame(width: 332)
            }
        }
    }

    private var dictationsCard: some View {
        insightCard {
            Text(UsageInsights.grouped(insights.dictationCount))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text("Dictations")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .textCase(.uppercase)
            Text(insights.uniqueAppCount == 1 ? "1 app" : "\(insights.uniqueAppCount) apps")
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
                .padding(.top, 8)
        }
    }

    private var fixesCard: some View {
        insightCard {
            Text(UsageInsights.grouped(insights.totalFixes))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text("Fixes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 4) {
                labeledCount(insights.wordsCorrected, label: "words corrected")
                labeledCount(insights.dictionaryFixes, label: "dictionary fixes")
            }
            .padding(.top, 10)
        }
    }

    private var wordsCard: some View {
        insightCard {
            Text(insights.formattedWordCount)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text("Total words dictated")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .textCase(.uppercase)
            if let milestone = insights.wordMilestone {
                Text(milestone)
                    .font(.system(size: 13))
                    .foregroundStyle(FlowTheme.muted)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var desktopUsageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Desktop usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                Spacer()
                Text("Total apps used")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Text("\(insights.uniqueAppCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
            }

            if insights.dictationCount == 0 {
                Text("Hold Fn to dictate. App breakdown shows up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(FlowTheme.muted)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(insights.categories.filter { $0.dictationCount > 0 }) { row in
                        categoryRow(row)
                    }
                }

                if !insights.apps.isEmpty {
                    Rectangle()
                        .fill(FlowTheme.hairline)
                        .frame(height: 1)
                        .padding(.top, 4)

                    HStack {
                        Text("Where you dictate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted)
                            .tracking(0.4)
                            .textCase(.uppercase)
                        Spacer()
                        Text("Words")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted)
                            .tracking(0.4)
                            .textCase(.uppercase)
                    }

                    let leader = insights.apps.first?.wordCount ?? 1
                    VStack(spacing: 12) {
                        ForEach(insights.apps.prefix(6)) { app in
                            appRow(app, leaderWords: leader)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(insights.currentStreak == 1 ? "1 day streak" : "\(insights.currentStreak) day streak")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                Spacer()
                Text("Longest")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Text(insights.longestStreak == 1 ? "1 day" : "\(insights.longestStreak) days")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
            }

            StreakHeatmapView(
                days: insights.days,
                monthOffset: $monthOffset
            )

            HStack(spacing: 6) {
                Text("Less")
                    .font(.system(size: 10))
                    .foregroundStyle(FlowTheme.muted)
                heatmapSwatch(FlowTheme.card)
                heatmapSwatch(FlowTheme.insightSoft)
                heatmapSwatch(FlowTheme.insightMid)
                heatmapSwatch(FlowTheme.insight)
                Text("More")
                    .font(.system(size: 10))
                    .foregroundStyle(FlowTheme.muted)
                Spacer()
                Button {
                    monthOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlowTheme.muted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Earlier months")
                Button {
                    monthOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(monthOffset < 0 ? FlowTheme.muted : FlowTheme.hairline)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(monthOffset >= 0)
                .help("Later months")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var voicePane: some View {
        Group {
            if insights.dictationCount == 0 {
                Text("Dictate for a while and this tab will show your catchphrases, common words, and peak hours — from your history only.")
                    .font(.system(size: 14))
                    .foregroundStyle(FlowTheme.muted)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        quoteCard(
                            title: "Catchphrase",
                            value: insights.catchphrase.map { "“\($0)”" } ?? "Not enough repetition yet"
                        )
                        quoteCard(
                            title: "Most used word",
                            value: insights.mostUsedWord.map { "“\($0)”" } ?? "Keep dictating"
                        )
                    }
                    .frame(maxWidth: .infinity)

                    peakTimeCard
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func quoteCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(FlowTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var peakTimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(insights.peakTimeLabel() ?? "No peak hour yet")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your peak time")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .textCase(.uppercase)
            if let peak = insights.peakTimeLabel() {
                Text(peakDetail(for: peak))
                    .font(.system(size: 14))
                    .foregroundStyle(FlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func peakDetail(for peak: String) -> String {
        if let app = insights.peakAppName {
            return "Most of your words land around \(peak.lowercased()), often in \(app)."
        }
        return "Most of your words land around \(peak.lowercased())."
    }

    private func categoryRow(_ row: UsageCategoryRow) -> some View {
        let percent = Int((row.fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: row.category.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.insight)
                    .frame(width: 16)

                Text(row.category.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)

                Text(UsageInsights.grouped(row.dictationCount))
                    .font(.system(size: 12))
                    .foregroundStyle(FlowTheme.muted)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(FlowTheme.card)
                    Capsule()
                        .fill(percent == 0 ? Color.clear : FlowTheme.insight)
                        .frame(width: geo.size.width * row.fraction)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.category.title), \(percent) percent, \(row.dictationCount) dictations")
    }

    private func appRow(_ app: UsageAppRow, leaderWords: Int) -> some View {
        let percent = insights.totalWords == 0
            ? 0
            : Int((Double(app.wordCount) / Double(insights.totalWords) * 100).rounded())
        let share = leaderWords == 0 ? 0 : Double(app.wordCount) / Double(leaderWords)
        return HStack(spacing: 10) {
            appIcon(bundleID: app.bundleID, name: app.name)

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FlowTheme.card)
                        Capsule()
                            .fill(FlowTheme.insight.opacity(0.85))
                            .frame(width: max(geo.size.width * share, share > 0 ? 4 : 0))
                    }
                }
                .frame(height: 4)
            }

            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)

            Text(UsageInsights.grouped(app.wordCount))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FlowTheme.ink)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(percent) percent, \(app.wordCount) words")
    }

    private func appIcon(bundleID: String?, name: String) -> some View {
        Group {
            if let icon = AppIconCache.icon(bundleID: bundleID, appName: name) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func labeledCount(_ count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Text(UsageInsights.grouped(count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
        }
    }

    private func insightCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func heatmapSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(FlowTheme.hairline, lineWidth: 1)
            )
    }
}

private struct StreakHeatmapView: View {
    let days: [Date: UsageDay]
    @Binding var monthOffset: Int

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        let grid = Self.makeGrid(days: days, monthOffset: monthOffset)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 18, height: 1)
                HStack(spacing: 0) {
                    ForEach(Array(grid.monthLabels.enumerated()), id: \.offset) { _, tick in
                        Text(tick.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FlowTheme.muted)
                            .lineLimit(1)
                            .frame(
                                width: CGFloat(tick.span) * (cell + gap),
                                alignment: .leading
                            )
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: gap) {
                    ForEach(Array(grid.weekdayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FlowTheme.muted)
                            .frame(width: 12, height: cell, alignment: .leading)
                    }
                }

                HStack(spacing: gap) {
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, cellModel in
                                heatmapCell(cellModel, maxWords: grid.maxWords)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func heatmapCell(_ model: HeatmapCell?, maxWords: Int) -> some View {
        if let model {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(fillColor(for: model, maxWords: maxWords))
                .frame(width: cell, height: cell)
                .help(model.help)
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func fillColor(for model: HeatmapCell, maxWords: Int) -> Color {
        if model.isFuture { return FlowTheme.card.opacity(0.35) }
        if model.words <= 0 { return FlowTheme.card }
        let t = Double(model.words) / Double(max(maxWords, 1))
        if t < 0.22 { return FlowTheme.insightSoft }
        if t < 0.55 { return FlowTheme.insightMid }
        return FlowTheme.insight
    }

    private struct HeatmapCell {
        let date: Date
        let words: Int
        let dictations: Int
        let isFuture: Bool

        var help: String {
            let day = date.formatted(.dateTime.month(.abbreviated).day().year())
            if isFuture { return day }
            if dictations == 0 { return "\(day) · no dictations" }
            return "\(day) · \(dictations) dictation\(dictations == 1 ? "" : "s") · \(words) words"
        }
    }

    private struct HeatmapGrid {
        var weeks: [[HeatmapCell?]]
        var weekdayLabels: [String]
        var monthLabels: [(label: String, span: Int)]
        var maxWords: Int
    }

    private static func makeGrid(
        days: [Date: UsageDay],
        monthOffset: Int
    ) -> HeatmapGrid {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let today = calendar.startOfDay(for: Date())
        let endAnchor = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let startAnchor = calendar.date(byAdding: .month, value: -4, to: endAnchor) ?? endAnchor
        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startAnchor)) ?? startAnchor
        let weekday = calendar.component(.weekday, from: startMonth)
        let gridStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: startMonth) ?? startMonth

        let rangeEnd: Date = {
            if monthOffset >= 0 { return today }
            let comps = calendar.dateComponents([.year, .month], from: endAnchor)
            guard let monthStart = calendar.date(from: comps),
                  let next = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { return endAnchor }
            return calendar.date(byAdding: .day, value: -1, to: next) ?? endAnchor
        }()

        var weeks: [[HeatmapCell?]] = []
        var cursor = gridStart
        var maxWords = 1
        var weekCount = 0
        while cursor <= rangeEnd, weekCount < 32 {
            var week: [HeatmapCell?] = []
            for _ in 0..<7 {
                let isFuture = cursor > today
                let usage = days[cursor]
                let words = usage?.wordCount ?? 0
                maxWords = max(maxWords, words)
                week.append(
                    HeatmapCell(
                        date: cursor,
                        words: words,
                        dictations: usage?.dictationCount ?? 0,
                        isFuture: isFuture
                    )
                )
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            weeks.append(week)
            weekCount += 1
        }

        var monthLabels: [(label: String, span: Int)] = []
        var lastMonth: Int?
        for week in weeks {
            guard !week.isEmpty, let mid = week[min(3, week.count - 1)] else { continue }
            let month = calendar.component(.month, from: mid.date)
            if lastMonth != month {
                monthLabels.append((
                    label: mid.date.formatted(.dateTime.month(.abbreviated)),
                    span: 1
                ))
                lastMonth = month
            } else if !monthLabels.isEmpty {
                monthLabels[monthLabels.count - 1].span += 1
            }
        }

        return HeatmapGrid(
            weeks: weeks,
            weekdayLabels: ["S", "M", "T", "W", "T", "F", "S"],
            monthLabels: monthLabels,
            maxWords: maxWords
        )
    }
}
