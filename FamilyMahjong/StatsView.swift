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

// MARK: - StatsView

struct StatsView: View {
    @Query(sort: \Player.name) private var players: [Player]

    private var winKing: Player? {
        players.max(by: { $0.winCount < $1.winCount })
    }
    private var loseKing: Player? {
        players.max(by: { $0.loseCount < $1.loseCount })
    }
    private var kongKing: Player? {
        players.max(by: { ($0.totalExposedKong + $0.totalConcealedKong) < ($1.totalExposedKong + $1.totalConcealedKong) })
    }

    private var hasAnyData: Bool {
        (winKing?.winCount ?? 0) > 0 ||
        (loseKing?.loseCount ?? 0) > 0 ||
        (kongKing.map { $0.totalExposedKong + $0.totalConcealedKong } ?? 0) > 0
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.statsRed, Color.statsRedDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if players.isEmpty || !hasAnyData {
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
                        titleSection
                        winKingCard
                        loseKingCard
                        kongKingCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("战绩统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleSection: some View {
        Text("趣味排行榜")
            .font(.title.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    private var winKingCard: some View {
        leaderboardCard(
            title: "大赢家 / 胡王",
            icon: "crown.fill",
            iconColor: Color.statsGold,
            player: winKing,
            value: winKing?.winCount ?? 0,
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
            value: loseKing?.loseCount ?? 0,
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
            value: kongKing.map { $0.totalExposedKong + $0.totalConcealedKong } ?? 0,
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

// MARK: - Preview

#Preview {
    NavigationStack {
        StatsView()
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
