//
//  ScoreResultView.swift
//  FamilyMahjong
//
//  单局结算结果页：趣味文案、四人本局得分/总积分、底部三按钮。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（春节卡通风）

private extension Color {
    static let resultRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let resultGold = Color(red: 244/255, green: 162/255, blue: 97/255)
    static let resultGoldLight = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let resultBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
    static let resultGreenDark = Color(red: 0.2, green: 0.5, blue: 0.35)
    static let resultGray = Color(red: 0.45, green: 0.45, blue: 0.45)
}

// MARK: - 趣味文案

private func funCopy(isSelfDrawn: Bool, roundNumber: Int) -> String {
    let selfDrawnCopies = [
        "🌟 自摸清一色，赢到手抽筋！",
        "🎉 自摸胡牌，三家掏钱！",
        "🔥 自摸一把，气势如虹！"
    ]
    let pointPayerCopies = [
        "💥 惨遭点炮，大出血啦！",
        "😭 点炮送分，心在滴血！",
        "💔 一炮三响，钱包空空！"
    ]
    let list = isSelfDrawn ? selfDrawnCopies : pointPayerCopies
    let index = roundNumber % list.count
    return list[index]
}

// MARK: - 玩家对（用作 Dictionary 键，需 Hashable）

private struct PlayerPair: Hashable {
    let id1: UUID
    let id2: UUID
}

// MARK: - ScoreResultView

struct ScoreResultView: View {
    let gameSession: GameSession
    let currentRecord: RoundRecord?
    @Binding var popToTableAfterResult: Bool
    /// 由选庄页传入时，点「原班人马」直接回到选庄页，跳过结算页
    var onPopToTable: (() -> Void)? = nil
    var onDismissToLobby: (() -> Void)?
    let scoringViewModel: ScoringViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var roundDeltas: [UUID: Int] {
        guard let record = currentRecord else { return [:] }
        return scoringViewModel.roundScoreDeltas(record: record, players: gameSession.players)
    }

    private var winnerID: UUID? { currentRecord?.winnerID }

    private var dealerID: UUID? { currentRecord?.dealerID }

    private var transfers: [(payerID: UUID, payeeID: UUID, amount: Int)] {
        guard let record = currentRecord else { return [] }
        return scoringViewModel.roundTransfers(record: record, players: gameSession.players)
    }

    /// 每对玩家只保留净值：A→B 与 B→A 合并为一条净转移（谁净付谁多少）
    private var netTransfers: [(payerID: UUID, payeeID: UUID, amount: Int)] {
        var gross: [PlayerPair: Int] = [:]
        for t in transfers {
            let key = PlayerPair(id1: t.payerID, id2: t.payeeID)
            gross[key, default: 0] += t.amount
        }
        var result: [(payerID: UUID, payeeID: UUID, amount: Int)] = []
        let playerIDs = gameSession.players.map(\.id)
        for i in 0 ..< playerIDs.count {
            for j in (i + 1) ..< playerIDs.count {
                let a = playerIDs[i], b = playerIDs[j]
                let ab = gross[PlayerPair(id1: a, id2: b), default: 0]
                let ba = gross[PlayerPair(id1: b, id2: a), default: 0]
                let net = ab - ba
                if net > 0 {
                    result.append((payerID: a, payeeID: b, amount: net))
                } else if net < 0 {
                    result.append((payerID: b, payeeID: a, amount: -net))
                }
            }
        }
        return result
    }

    /// 按出款方分组：payerID -> [(payeeID, amount)]（基于净值）
    private var groupedTransfersByPayer: [UUID: [(payeeID: UUID, amount: Int)]] {
        var grouped: [UUID: [(payeeID: UUID, amount: Int)]] = [:]
        for t in netTransfers {
            grouped[t.payerID, default: []].append((payeeID: t.payeeID, amount: t.amount))
        }
        return grouped
    }

    /// 出款方展示顺序：按本桌玩家顺序，仅含确有出款的玩家
    private var orderedPayerIDs: [UUID] {
        gameSession.players.map(\.id).filter { groupedTransfersByPayer[$0] != nil }
    }

    private func player(by id: UUID) -> Player? {
        gameSession.players.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.resultBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    funCopyCard
                    scoreCardsSection
                    if !netTransfers.isEmpty {
                        transactionLogSection
                    }
                    bottomButtons
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("算分结果")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 顶部趣味文案

    private var funCopyCard: some View {
        let isSelfDrawn = currentRecord?.isSelfDrawn ?? true
        let roundNumber = currentRecord?.roundNumber ?? 1
        let copy = funCopy(isSelfDrawn: isSelfDrawn, roundNumber: roundNumber)

        return Text(copy)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.resultRed)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
    }

    // MARK: - 分数卡片区

    private var scoreCardsSection: some View {
        VStack(spacing: 12) {
            ForEach(gameSession.players, id: \.id) { player in
                playerScoreCard(player: player)
            }
        }
    }

    private func playerScoreCard(player: Player) -> some View {
        let delta = roundDeltas[player.id] ?? 0
        let isWinner = player.id == winnerID
        let isDealer = player.id == dealerID
        let deltaText = delta >= 0 ? "+\(delta)" : "\(delta)"
        let deltaColor: Color = isWinner ? Color.resultRed : (delta < 0 ? Color.resultGreenDark : Color.resultGray)

        return HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                PlayerAvatarView(player: player, size: 56, iconColor: Color.resultRed)
                    .background(Color.white, in: Circle())
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                if isDealer {
                    Text("庄")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.resultGold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.resultGold.opacity(0.3), in: Capsule())
                        .overlay(Capsule().stroke(Color.resultRed, lineWidth: 1))
                        .offset(x: 4, y: -4)
                }
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.resultGold)
                        .offset(x: isDealer ? 20 : 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("总积分 \(scoringViewModel.getTotalScore(for: player, context: modelContext))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(deltaText)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(deltaColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isWinner ? Color.resultGold : Color.clear, lineWidth: 3)
        )
    }

    // MARK: - 本局积分流转

    private var transactionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本局积分流转")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.resultRed)

            ForEach(orderedPayerIDs, id: \.self) { payerID in
                payerCard(payerID: payerID)
            }
        }
    }

    /// 单个出款方大框：框顶出款方头像+姓名，框内多行「给谁多少分」
    private func payerCard(payerID: UUID) -> some View {
        let items = groupedTransfersByPayer[payerID] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            if let payer = player(by: payerID) {
                HStack(spacing: 8) {
                    smallPlayerChip(player: payer)
                    Text("付给")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(0 ..< items.count, id: \.self) { index in
                let item = items[index]
                transferLine(payeeID: item.payeeID, amount: item.amount)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
    }

    /// 单行：→ XX 分 → 收款人
    private func transferLine(payeeID: UUID, amount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.resultGold)
            Text("\(amount) 分")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.resultRed, in: Capsule())
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.resultGold)
            if let payee = player(by: payeeID) {
                smallPlayerChip(player: payee)
            }
            Spacer(minLength: 0)
        }
    }

    private func smallPlayerChip(player: Player) -> some View {
        let isDealer = player.id == dealerID
        return HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PlayerAvatarView(player: player, size: 32, iconColor: Color.resultRed)
                if isDealer {
                    Text("庄")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.resultGold)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.resultGold.opacity(0.3), in: Capsule())
                        .overlay(Capsule().stroke(Color.resultRed, lineWidth: 1))
                        .offset(x: 2, y: -2)
                }
            }
            Text(player.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - 底部三按钮

    private var bottomButtons: some View {
        VStack(spacing: 14) {
            Button {
                if let onPopToTable {
                    onPopToTable()
                } else {
                    popToTableAfterResult = true
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                    Text("继续：原班人马下一局！")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.resultGreenDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.resultGreenDark, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                onDismissToLobby?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                    Text("换人 / 返回大厅")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.resultGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            NavigationLink(destination: RecentMatchLogWrapperView(onPopToRoot: onDismissToLobby)) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.title2)
                    Text("查看历史日志")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.resultRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            NavigationLink(destination: StatsView(onPopToRoot: onDismissToLobby)) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                    Text("查看战绩统计")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.resultRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

// MARK: - 按压缩放按钮样式

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let session = GameSession(currentDealerID: UUID())
    session.players.append(contentsOf: [
        Player(name: "爸爸", avatarIcon: "person.circle.fill"),
        Player(name: "妈妈", avatarIcon: "person.circle.fill"),
        Player(name: "叔叔", avatarIcon: "person.circle.fill"),
        Player(name: "阿姨", avatarIcon: "person.circle.fill")
    ])
    return NavigationStack {
        ScoreResultView(
            gameSession: session,
            currentRecord: nil,
            popToTableAfterResult: .constant(false),
            onDismissToLobby: nil,
            scoringViewModel: ScoringViewModel()
        )
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
