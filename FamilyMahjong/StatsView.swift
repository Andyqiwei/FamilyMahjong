//
//  StatsView.swift
//  FamilyMahjong
//
//  趣味排行榜：大赢家、点炮王、杠精转世。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（深色/喜庆红背景 + 金/白卡片）

private extension Color {
    static let statsRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let statsRedDark = Color(red: 180/255, green: 40/255, blue: 55/255)
    static let statsGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let statsGoldDark = Color(red: 244/255, green: 162/255, blue: 97/255)
    static let statsCardBg = Color(red: 255/255, green: 252/255, blue: 248/255)
}

// MARK: - 主 Tab / 详细范围

private enum MainTab: String, CaseIterable {
    case funRanking = "朱家大榜"
    case detailedData = "详细数据"
}

private enum DetailScope: String, CaseIterable {
    case total = "总计"
    case today = "今日"
    case dailyHistory = "历史每日"
}

// MARK: - StatsView

struct StatsView: View {
    var onPopToRoot: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: \RoundRecord.timestamp, order: .reverse) private var allRecords: [RoundRecord]
    @StateObject private var scoringViewModel = ScoringViewModel()
    @State private var mainTab: MainTab = .funRanking
    @State private var detailScope: DetailScope = .total

    private var winKing: Player? {
        players.max(by: { scoringViewModel.getWinCount(for: $0, context: modelContext) < scoringViewModel.getWinCount(for: $1, context: modelContext) })
    }
    private var loseKing: Player? {
        players.max(by: { scoringViewModel.getLoseCount(for: $0, context: modelContext) < scoringViewModel.getLoseCount(for: $1, context: modelContext) })
    }
    private var kongKing: Player? {
        players.max(by: { scoringViewModel.getTotalKongs(for: $0, context: modelContext) < scoringViewModel.getTotalKongs(for: $1, context: modelContext) })
    }

    private var hasAnyData: Bool {
        (winKing.map { scoringViewModel.getWinCount(for: $0, context: modelContext) } ?? 0) > 0 ||
        (loseKing.map { scoringViewModel.getLoseCount(for: $0, context: modelContext) } ?? 0) > 0 ||
        (kongKing.map { scoringViewModel.getTotalKongs(for: $0, context: modelContext) } ?? 0) > 0
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.statsRed, Color.statsRedDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if players.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Color.statsGold)
                    Text("暂无数据，大家继续努力")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        Picker("", selection: $mainTab) {
                            ForEach(MainTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 4)

                        if mainTab == .funRanking {
                            titleSection
                            winKingCard
                            loseKingCard
                            kongKingCard
                        } else {
                            detailedDataSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("战绩统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let pop = onPopToRoot {
                        pop()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "house.fill")
                        .foregroundStyle(Color.statsRed)
                }
            }
        }
    }

    private var titleSection: some View {
        Text("朱家琅琊榜")
            .font(.title.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    private var detailedDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $detailScope) {
                ForEach(DetailScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)

            switch detailScope {
            case .total:
                if allRecords.isEmpty {
                    detailedDataEmptyView
                } else {
                    StatTableView(players: players, records: allRecords, viewModel: scoringViewModel)
                }
            case .today:
                let todayRecords = allRecords.filter { Calendar.current.isDateInToday($0.timestamp) }
                if todayRecords.isEmpty {
                    detailedDataEmptyView
                } else {
                    StatTableView(players: players, records: todayRecords, viewModel: scoringViewModel)
                }
            case .dailyHistory:
                let byDay = scoringViewModel.groupRecordsByDay(records: allRecords)
                if byDay.isEmpty {
                    detailedDataEmptyView
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(byDay.enumerated()), id: \.offset) { _, day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.white)
                                    StatTableView(players: players, records: day.records, viewModel: scoringViewModel)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var detailedDataEmptyView: some View {
        Text("暂无详细数据")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private var winKingCard: some View {
        leaderboardCard(
            title: "大赢家 / 胡王",
            icon: "crown.fill",
            iconColor: Color.statsGold,
            player: winKing,
            value: winKing.map { scoringViewModel.getWinCount(for: $0, context: modelContext) } ?? 0,
            valueLabel: "总胡牌次数",
            emptyMessage: "暂无数据，大家继续努力"
        )
    }

    private var loseKingCard: some View {
        leaderboardCard(
            title: "点炮王 / 最佳慈善家",
            icon: "flame.fill",
            iconColor: Color.orange,
            player: loseKing,
            value: loseKing.map { scoringViewModel.getLoseCount(for: $0, context: modelContext) } ?? 0,
            valueLabel: "总点炮次数",
            emptyMessage: "暂无数据，大家继续努力"
        )
    }

    private var kongKingCard: some View {
        leaderboardCard(
            title: "杠精转世",
            icon: "dumbbell.fill",
            iconColor: Color.statsRed,
            player: kongKing,
            value: kongKing.map { scoringViewModel.getTotalKongs(for: $0, context: modelContext) } ?? 0,
            valueLabel: "总杠牌次数",
            emptyMessage: "暂无数据，大家继续努力"
        )
    }

    private func leaderboardCard(
        title: String,
        icon: String,
        iconColor: Color,
        player: Player?,
        value: Int,
        valueLabel: String,
        emptyMessage: String
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.statsRedDark)
            }
            .frame(maxWidth: .infinity)

            if let p = player, value > 0 {
                HStack(spacing: 16) {
                        PlayerAvatarView(player: p, size: 56, iconColor: Color.statsRed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("\(valueLabel)：\(value)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            } else {
                Text(emptyMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.statsCardBg)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.statsGold.opacity(0.4), lineWidth: 2)
        )
    }
}

// MARK: - StatTableView（左列固定，右列横向滑动）

private struct StatTableView: View {
    let players: [Player]
    let records: [RoundRecord]
    @ObservedObject var viewModel: ScoringViewModel

    private let leftColumnWidth: CGFloat = 110
    private let dataColumnWidth: CGFloat = 60
    private let dataColumns = ["积分变动", "胡", "自摸", "点炮", "明杠", "暗杠"]

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
            ScrollView(.horizontal, showsIndicators: true) {
                dataColumnsView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.statsCardBg)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.statsGold.opacity(0.4), lineWidth: 2)
        )
    }

    private var leftColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("玩家")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.statsRedDark)
                    .frame(width: leftColumnWidth - 12, alignment: .leading)
            }
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(Color.statsGold.opacity(0.25))

            ForEach(players, id: \.id) { player in
                HStack(spacing: 6) {
                    PlayerAvatarView(player: player, size: 32, iconColor: Color.statsRed)
                    Text(player.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(width: leftColumnWidth - 12, height: 44, alignment: .leading)
                .padding(.horizontal, 8)
            }
        }
        .frame(width: leftColumnWidth, alignment: .leading)
    }

    private var dataColumnsView: some View {
        HStack(spacing: 0) {
            ForEach(Array(dataColumns.enumerated()), id: \.offset) { index, title in
                VStack(spacing: 0) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.statsRedDark)
                        .frame(width: dataColumnWidth, height: 36)
                        .background(Color.statsGold.opacity(0.25))

                    ForEach(players, id: \.id) { player in
                        let detail = viewModel.aggregateStats(for: player, in: records, allPlayers: players)
                        cellView(detail: detail, columnIndex: index)
                            .frame(width: dataColumnWidth, height: 44)
                    }
                }
            }
        }
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private func cellView(detail: PlayerStatDetail, columnIndex: Int) -> some View {
        Group {
            switch columnIndex {
            case 0:
                let delta = detail.scoreDelta
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(delta > 0 ? Color.statsRed : (delta < 0 ? Color.green : Color.secondary))
            case 1: Text("\(detail.win)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            case 2: Text("\(detail.selfDrawn)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            case 3: Text("\(detail.lose)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            case 4: Text("\(detail.exposedKong)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            case 5: Text("\(detail.concealedKong)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatsView()
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
