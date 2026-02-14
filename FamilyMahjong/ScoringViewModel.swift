//
//  ScoringViewModel.swift
//  FamilyMahjong
//
//  牌局算分引擎：处理 GameSession 的结算与撤销，所有分数转移经 transferScore 以套用庄家翻倍。
//

import Foundation
import Combine

/// 算分引擎：负责单局结算、杠牌结算、统计更新与撤销。不持有 ModelContext，由调用方在合适 context 中保存。
final class ScoringViewModel: ObservableObject {

    // MARK: - 庄家翻倍法则（私有辅助）

    /// 从 payer 向 payee 转移分数；若 payer 或 payee 为庄家则实际转移 baseScore * 2，否则 baseScore。
    /// 所有胡牌、杠牌转账必须经此函数以保证庄家翻倍一致。
    private func transferScore(from payer: Player, to payee: Player, baseScore: Int, dealerID: UUID) {
        let actual = (payer.id == dealerID || payee.id == dealerID) ? baseScore * 2 : baseScore
        payer.totalScore -= actual
        payee.totalScore += actual
    }

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

    // MARK: - 主结算

    /// 根据本局结果计算并应用分数，更新统计，并追加一条 RoundRecord。
    /// 调用方需保证 session.players 为 4 人且 winnerID/loserID/kongs 中的 playerID 均能在 session.players 中找到。
    func calculateAndApplyRound(
        session: GameSession,
        winnerID: UUID,
        loserID: UUID?,
        isSelfDrawn: Bool,
        kongs: [KongDetail]
    ) {
        let players = session.players
        guard players.count == 4 else { return }
        guard let winner = players.first(where: { $0.id == winnerID }) else { return }
        if !isSelfDrawn, let lid = loserID, players.first(where: { $0.id == lid }) == nil { return }

        let dealerID = session.currentDealerID
        let others = players.filter { $0.id != winnerID }
        assert(others.count == 3, "应有 3 家非赢家")

        // 1. 胡牌分数转移
        if isSelfDrawn {
            // 自摸：其余三家各向赢家转 20 分
            for other in others {
                transferScore(from: other, to: winner, baseScore: 20, dealerID: dealerID)
            }
        } else {
            // 点炮：点炮者向赢家转 20 分，另两家各转 10 分
            if let lid = loserID, let loser = players.first(where: { $0.id == lid }) {
                transferScore(from: loser, to: winner, baseScore: 20, dealerID: dealerID)
                for other in others where other.id != lid {
                    transferScore(from: other, to: winner, baseScore: 10, dealerID: dealerID)
                }
            }
        }

        // 2. 杠牌分数转移
        for kong in kongs {
            guard let kongTaker = players.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = players.filter { $0.id != kong.playerID }
            if kong.exposedKongCount > 0 {
                let base = 10 * kong.exposedKongCount
                for payer in kongPayers {
                    transferScore(from: payer, to: kongTaker, baseScore: base, dealerID: dealerID)
                }
            }
            if kong.concealedKongCount > 0 {
                let base = 20 * kong.concealedKongCount
                for payer in kongPayers {
                    transferScore(from: payer, to: kongTaker, baseScore: base, dealerID: dealerID)
                }
            }
        }

        // 3. 更新玩家统计
        winner.winCount += 1
        if let lid = loserID, let loser = players.first(where: { $0.id == lid }) {
            loser.loseCount += 1
        }
        for kong in kongs {
            if let p = players.first(where: { $0.id == kong.playerID }) {
                p.totalExposedKong += kong.exposedKongCount
                p.totalConcealedKong += kong.concealedKongCount
            }
        }

        // 4. 生成并追加 RoundRecord
        let roundNumber = session.roundRecords.count + 1
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

    // MARK: - 撤销

    /// 撤销某一局：按 record 反向执行分数转移与统计回退，并从 session 中移除该记录。
    func undoRound(record: RoundRecord, session: GameSession) {
        let players = session.players
        guard players.count == 4 else { return }
        guard let winner = players.first(where: { $0.id == record.winnerID }) else { return }

        let dealerID = record.dealerID
        let others = players.filter { $0.id != record.winnerID }
        assert(others.count == 3)

        // 1. 反向胡牌分数
        if record.isSelfDrawn {
            for other in others {
                transferScore(from: winner, to: other, baseScore: 20, dealerID: dealerID)
            }
        } else {
            if let lid = record.loserID, let loser = players.first(where: { $0.id == lid }) {
                transferScore(from: winner, to: loser, baseScore: 20, dealerID: dealerID)
                for other in others where other.id != lid {
                    transferScore(from: winner, to: other, baseScore: 10, dealerID: dealerID)
                }
            }
        }

        // 2. 反向杠牌分数
        for kong in record.kongDetails {
            guard let kongTaker = players.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = players.filter { $0.id != kong.playerID }
            if kong.exposedKongCount > 0 {
                let base = 10 * kong.exposedKongCount
                for payer in kongPayers {
                    transferScore(from: kongTaker, to: payer, baseScore: base, dealerID: dealerID)
                }
            }
            if kong.concealedKongCount > 0 {
                let base = 20 * kong.concealedKongCount
                for payer in kongPayers {
                    transferScore(from: kongTaker, to: payer, baseScore: base, dealerID: dealerID)
                }
            }
        }

        // 3. 回退统计
        winner.winCount -= 1
        if let lid = record.loserID, let loser = players.first(where: { $0.id == lid }) {
            loser.loseCount -= 1
        }
        for kong in record.kongDetails {
            if let p = players.first(where: { $0.id == kong.playerID }) {
                p.totalExposedKong -= kong.exposedKongCount
                p.totalConcealedKong -= kong.concealedKongCount
            }
        }

        // 4. 从 session 中移除该记录
        session.roundRecords.removeAll { $0.id == record.id }
        record.gameSession = nil
    }
}
