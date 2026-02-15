//
//  ScoringViewModel.swift
//  FamilyMahjong
//
//  牌局算分引擎：处理 GameSession 的结算与撤销，所有分数转移经 transferScore 以套用庄家翻倍。
//

import Foundation
import SwiftData
import Combine

/// 算分引擎：负责单局结算与撤销，RoundRecord 为唯一真相，统计由遍历 RoundRecord 实时计算。不持有 ModelContext，由调用方在合适 context 中保存。
final class ScoringViewModel: ObservableObject {

    // MARK: - 只读计算（本局）

    /// 只读计算本局每人得分变化（不修改 Player）。用于结果页展示。
    /// 返回 [playerID: 本局得分变化]，赢为正、输为负。
    func roundScoreDeltas(record: RoundRecord, players: [Player]) -> [UUID: Int] {
        var deltas: [UUID: Int] = [:]
        for p in players { deltas[p.id] = 0 }
        guard players.count == 4,
              let winner = players.first(where: { $0.id == record.winnerID }) else { return deltas }
        let others = players.filter { $0.id != record.winnerID }
        let dealerID = record.dealerID

        func addTransfer(payerID: UUID, payeeID: UUID, baseScore: Int) {
            let actual = (payerID == dealerID || payeeID == dealerID) ? baseScore * 2 : baseScore
            deltas[payerID, default: 0] -= actual
            deltas[payeeID, default: 0] += actual
        }

        // 1. 胡牌
        if record.isSelfDrawn {
            for other in others {
                addTransfer(payerID: other.id, payeeID: winner.id, baseScore: 20)
            }
        } else {
            if let lid = record.loserID, let loser = players.first(where: { $0.id == lid }) {
                addTransfer(payerID: loser.id, payeeID: winner.id, baseScore: 20)
                for other in others where other.id != lid {
                    addTransfer(payerID: other.id, payeeID: winner.id, baseScore: 10)
                }
            }
        }

        // 2. 杠牌
        for kong in record.kongDetails {
            guard let kongTaker = players.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = players.filter { $0.id != kong.playerID }
            if kong.exposedKongCount > 0 {
                let base = 10 * kong.exposedKongCount
                for payer in kongPayers {
                    addTransfer(payerID: payer.id, payeeID: kongTaker.id, baseScore: base)
                }
            }
            if kong.concealedKongCount > 0 {
                let base = 20 * kong.concealedKongCount
                for payer in kongPayers {
                    addTransfer(payerID: payer.id, payeeID: kongTaker.id, baseScore: base)
                }
            }
        }

        return deltas
    }

    /// 只读生成本局逐笔积分转移列表（谁给谁多少分），用于结果页流转展示。仅包含 amount > 0 的条目。
    func roundTransfers(record: RoundRecord, players: [Player]) -> [(payerID: UUID, payeeID: UUID, amount: Int)] {
        var result: [(payerID: UUID, payeeID: UUID, amount: Int)] = []
        guard players.count == 4,
              let winner = players.first(where: { $0.id == record.winnerID }) else { return result }
        let others = players.filter { $0.id != record.winnerID }
        let dealerID = record.dealerID

        func appendTransfer(payerID: UUID, payeeID: UUID, baseScore: Int) {
            let actual = (payerID == dealerID || payeeID == dealerID) ? baseScore * 2 : baseScore
            if actual > 0 {
                result.append((payerID: payerID, payeeID: payeeID, amount: actual))
            }
        }

        // 1. 胡牌
        if record.isSelfDrawn {
            for other in others {
                appendTransfer(payerID: other.id, payeeID: winner.id, baseScore: 20)
            }
        } else {
            if let lid = record.loserID, let loser = players.first(where: { $0.id == lid }) {
                appendTransfer(payerID: loser.id, payeeID: winner.id, baseScore: 20)
                for other in others where other.id != lid {
                    appendTransfer(payerID: other.id, payeeID: winner.id, baseScore: 10)
                }
            }
        }

        // 2. 杠牌
        for kong in record.kongDetails {
            guard let kongTaker = players.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = players.filter { $0.id != kong.playerID }
            if kong.exposedKongCount > 0 {
                let base = 10 * kong.exposedKongCount
                for payer in kongPayers {
                    appendTransfer(payerID: payer.id, payeeID: kongTaker.id, baseScore: base)
                }
            }
            if kong.concealedKongCount > 0 {
                let base = 20 * kong.concealedKongCount
                for payer in kongPayers {
                    appendTransfer(payerID: payer.id, payeeID: kongTaker.id, baseScore: base)
                }
            }
        }

        return result
    }

    // MARK: - 当日局数

    /// 获取今天（自然日 0–24 点）在库里的所有 RoundRecord 数量 + 1，作为下一局的局号。
    func getNextRoundNumberForToday(context: ModelContext) -> Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return 1 }

        let descriptor = FetchDescriptor<RoundRecord>(
            predicate: #Predicate<RoundRecord> { record in
                record.timestamp >= startOfToday && record.timestamp < startOfNextDay
            }
        )
        let count = (try? context.fetch(descriptor).count) ?? 0
        return count + 1
    }

    // MARK: - 主结算（仅增 RoundRecord）

    /// 根据本局结果追加一条 RoundRecord。分数与统计由 RoundRecord 唯一真相，通过 getTotalScore 等实时计算。
    /// 调用方需保证 session.players 为 4 人且 winnerID/loserID/kongs 中的 playerID 均能在 session.players 中找到。
    func calculateAndApplyRound(
        session: GameSession,
        roundNumber: Int,
        winnerID: UUID,
        loserID: UUID?,
        isSelfDrawn: Bool,
        kongs: [KongDetail]
    ) {
        let players = session.players
        guard players.count == 4 else { return }
        guard players.first(where: { $0.id == winnerID }) != nil else { return }

        let dealerID = session.currentDealerID
        let newRecord = RoundRecord(
            roundNumber: roundNumber,
            winnerID: winnerID,
            loserID: loserID,
            isSelfDrawn: isSelfDrawn,
            kongDetails: kongs,
            gameSession: session,
            dealerID: dealerID
        )
        session.roundRecords.append(newRecord)
        newRecord.gameSession = session
    }

    // MARK: - 撤销（仅删 RoundRecord）

    /// 撤销某一局：从 session 中移除该记录。分数与统计由 RoundRecord 唯一真相，移除后通过 get* 实时计算即更新。
    func undoRound(record: RoundRecord, session: GameSession) {
        session.roundRecords.removeAll { $0.id == record.id }
        record.gameSession = nil
    }

    // MARK: - 编辑更新（仅改 RoundRecord）

    /// 更新已有记录：直接改写 record 字段，不修改 Player。统计由 RoundRecord 唯一真相实时计算。
    func updateRound(
        record: RoundRecord,
        session: GameSession,
        winnerID: UUID,
        loserID: UUID?,
        isSelfDrawn: Bool,
        kongs: [KongDetail]
    ) {
        record.winnerID = winnerID
        record.loserID = loserID
        record.isSelfDrawn = isSelfDrawn
        record.kongDetails = kongs
        record.timestamp = Date()
    }

    // MARK: - 全局统计（遍历 RoundRecord 实时计算）

    /// 所有涉及该玩家的 RoundRecord（赢家、点炮或杠牌参与）。
    private func recordsInvolving(player: Player, context: ModelContext) -> [RoundRecord] {
        let descriptor = FetchDescriptor<RoundRecord>()
        guard let allRecords = try? context.fetch(descriptor) else { return [] }
        let playerID = player.id
        return allRecords.filter { record in
            record.winnerID == playerID ||
            record.loserID == playerID ||
            record.kongDetails.contains { $0.playerID == playerID }
        }
    }

    /// 该玩家总积分（所有参与局得分变化之和）。
    func getTotalScore(for player: Player, context: ModelContext) -> Int {
        let records = recordsInvolving(player: player, context: context)
        let playerID = player.id
        var total = 0
        for record in records {
            guard let players = record.gameSession?.players, players.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: players)
            total += deltas[playerID] ?? 0
        }
        return total
    }

    /// 该玩家总胡牌次数。
    func getWinCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.winnerID == player.id }.count
    }

    /// 该玩家总点炮次数。
    func getLoseCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.loserID == player.id }.count
    }

    /// 该玩家总杠牌次数（明杠 + 暗杠）。
    func getTotalKongs(for player: Player, context: ModelContext) -> Int {
        let records = recordsInvolving(player: player, context: context)
        let playerID = player.id
        return records.reduce(0) { sum, record in
            let k = record.kongDetails.first { $0.playerID == playerID }
            return sum + (k.map { $0.exposedKongCount + $0.concealedKongCount } ?? 0)
        }
    }

    // MARK: - 当日积分变动

    /// 查询该玩家在今天参与的所有 RoundRecord，计算当日积分净变动（赢为正、输为负）。
    func getTodayScoreDelta(for player: Player, context: ModelContext) -> Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return 0 }

        var descriptor = FetchDescriptor<RoundRecord>(
            predicate: #Predicate<RoundRecord> { record in
                record.timestamp >= startOfToday && record.timestamp < startOfNextDay
            }
        )

        guard let todayRecords = try? context.fetch(descriptor) else { return 0 }

        let playerID = player.id
        let participatingRecords = todayRecords.filter { record in
            record.winnerID == playerID ||
            record.loserID == playerID ||
            record.kongDetails.contains { $0.playerID == playerID }
        }

        var totalDelta = 0
        for record in participatingRecords {
            guard let players = record.gameSession?.players, players.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: players)
            totalDelta += deltas[playerID] ?? 0
        }

        return totalDelta
    }
}
