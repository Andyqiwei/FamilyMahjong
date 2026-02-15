//
//  ScoringViewModel.swift
//  FamilyMahjong
//
//  牌局算分引擎：处理 GameSession 的结算与撤销，所有分数转移经 transferScore 以套用庄家翻倍。
//

import Foundation
import SwiftData
import Combine

/// 单玩家聚合统计：用于详细数据报表。
struct PlayerStatDetail {
    var scoreDelta: Int = 0
    var win: Int = 0
    var selfDrawn: Int = 0
    var lose: Int = 0
    var exposedKong: Int = 0
    var concealedKong: Int = 0
}

/// 算分引擎：负责单局结算与撤销，RoundRecord 为唯一真相，统计由遍历 RoundRecord 实时计算。
final class ScoringViewModel: ObservableObject {

    // MARK: - 只读计算（本局）

    /// 只读计算本局每人得分变化。仅对 record 内显式出现的玩家算分，避免旁观者被错误扣分。
    func roundScoreDeltas(record: RoundRecord, players: [Player]) -> [UUID: Int] {
        var deltas: [UUID: Int] = [:]
        for p in players { deltas[p.id] = 0 }

        if record.isAdjustment {
            for adj in record.adjustments {
                if let p = players.first(where: { $0.name.trimmingCharacters(in: .whitespaces) == adj.playerName.trimmingCharacters(in: .whitespaces) }) {
                    deltas[p.id, default: 0] += adj.delta
                }
            }
            return deltas
        }

        var tablePlayerIDs: Set<UUID> = [record.winnerID, record.dealerID]
        if let lid = record.loserID { tablePlayerIDs.insert(lid) }
        for k in record.kongDetails { tablePlayerIDs.insert(k.playerID) }
        let tablePlayers = players.filter { tablePlayerIDs.contains($0.id) }

        guard let winner = tablePlayers.first(where: { $0.id == record.winnerID }) else { return deltas }
        let others = tablePlayers.filter { $0.id != record.winnerID }
        let dealerID = record.dealerID

        func addTransfer(payerID: UUID, payeeID: UUID, baseScore: Int) {
            let actual = (payerID == dealerID || payeeID == dealerID) ? baseScore * 2 : baseScore
            deltas[payerID, default: 0] -= actual
            deltas[payeeID, default: 0] += actual
        }

        // 1. 胡牌：仅对 record 内桌上玩家算分
        if record.isSelfDrawn {
            for other in others {
                addTransfer(payerID: other.id, payeeID: winner.id, baseScore: 20)
            }
        } else {
            if let lid = record.loserID, let loser = tablePlayers.first(where: { $0.id == lid }) {
                addTransfer(payerID: loser.id, payeeID: winner.id, baseScore: 20)
                for other in others where other.id != lid {
                    addTransfer(payerID: other.id, payeeID: winner.id, baseScore: 10)
                }
            }
        }

        // 2. 杠牌：仅对 record 内桌上玩家算分
        for kong in record.kongDetails {
            guard let kongTaker = tablePlayers.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = tablePlayers.filter { $0.id != kong.playerID }
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

    /// 只读生成本局逐笔积分转移列表（仅用于结果页展示）。仅对 record 内桌上玩家算分。
    func roundTransfers(record: RoundRecord, players: [Player]) -> [(payerID: UUID, payeeID: UUID, amount: Int)] {
        if record.isAdjustment { return [] }
        var result: [(payerID: UUID, payeeID: UUID, amount: Int)] = []

        var tablePlayerIDs: Set<UUID> = [record.winnerID, record.dealerID]
        if let lid = record.loserID { tablePlayerIDs.insert(lid) }
        for k in record.kongDetails { tablePlayerIDs.insert(k.playerID) }
        let tablePlayers = players.filter { tablePlayerIDs.contains($0.id) }

        guard let winner = tablePlayers.first(where: { $0.id == record.winnerID }) else { return result }
        let others = tablePlayers.filter { $0.id != record.winnerID }
        let dealerID = record.dealerID

        func appendTransfer(payerID: UUID, payeeID: UUID, baseScore: Int) {
            let actual = (payerID == dealerID || payeeID == dealerID) ? baseScore * 2 : baseScore
            if actual > 0 {
                result.append((payerID: payerID, payeeID: payeeID, amount: actual))
            }
        }

        if record.isSelfDrawn {
            for other in others {
                appendTransfer(payerID: other.id, payeeID: winner.id, baseScore: 20)
            }
        } else {
            if let lid = record.loserID, let loser = tablePlayers.first(where: { $0.id == lid }) {
                appendTransfer(payerID: loser.id, payeeID: winner.id, baseScore: 20)
                for other in others where other.id != lid {
                    appendTransfer(payerID: other.id, payeeID: winner.id, baseScore: 10)
                }
            }
        }

        for kong in record.kongDetails {
            guard let kongTaker = tablePlayers.first(where: { $0.id == kong.playerID }) else { continue }
            let kongPayers = tablePlayers.filter { $0.id != kong.playerID }
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

    // MARK: - 主结算与撤销

    @discardableResult
    func calculateAndApplyRound(
        session: GameSession,
        roundNumber: Int,
        winnerID: UUID,
        loserID: UUID?,
        isSelfDrawn: Bool,
        kongs: [KongDetail]
    ) -> RoundRecord? {
        let players = session.players
        guard players.first(where: { $0.id == winnerID }) != nil else { return nil }

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
        
        return newRecord
    }

    func undoRound(record: RoundRecord, session: GameSession) {
        session.roundRecords.removeAll { $0.id == record.id }
        record.gameSession = nil
    }

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
    }

    // MARK: - 全局统计（纯粹依赖 Log）

    /// 完全依赖 record 内显式 ID，不再使用 gameSession?.players，避免 CSV 导入断链。
    private func recordsInvolving(player: Player, context: ModelContext) -> [RoundRecord] {
        let descriptor = FetchDescriptor<RoundRecord>()
        guard let allRecords = try? context.fetch(descriptor) else { return [] }
        let playerID = player.id
        let playerNameTrimmed = player.name.trimmingCharacters(in: .whitespaces)
        return allRecords.filter { record in
            if record.isAdjustment {
                return record.adjustments.contains { $0.playerName.trimmingCharacters(in: .whitespaces) == playerNameTrimmed }
            }
            var involvedIDs: Set<UUID> = [record.winnerID, record.dealerID]
            if let lid = record.loserID { involvedIDs.insert(lid) }
            for k in record.kongDetails { involvedIDs.insert(k.playerID) }
            return involvedIDs.contains(playerID)
        }
    }

    func getTotalScore(for player: Player, context: ModelContext) -> Int {
        let records = recordsInvolving(player: player, context: context)
        let playerID = player.id
        var total = 0
        
        let descriptor = FetchDescriptor<Player>()
        let allPlayers = (try? context.fetch(descriptor)) ?? []

        for record in records {
            let deltas = roundScoreDeltas(record: record, players: allPlayers)
            total += deltas[playerID] ?? 0
        }
        return total
    }

    func getWinCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.winnerID == player.id && !$0.isAdjustment }.count
    }

    func getLoseCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.loserID == player.id && !$0.isAdjustment }.count
    }

    func getTotalKongs(for player: Player, context: ModelContext) -> Int {
        let records = recordsInvolving(player: player, context: context).filter { !$0.isAdjustment }
        let playerID = player.id
        return records.reduce(0) { sum, record in
            let k = record.kongDetails.first { $0.playerID == playerID }
            return sum + (k.map { $0.exposedKongCount + $0.concealedKongCount } ?? 0)
        }
    }

    // MARK: - 聚合统计（用于详细报表）

    func aggregateStats(for player: Player, in records: [RoundRecord], allPlayers: [Player]) -> PlayerStatDetail {
        var detail = PlayerStatDetail()
        let playerID = player.id

        for record in records {
            if record.isAdjustment { continue }

            if record.winnerID == playerID {
                detail.win += 1
                if record.isSelfDrawn { detail.selfDrawn += 1 }
            }
            if record.loserID == playerID { detail.lose += 1 }

            for kong in record.kongDetails where kong.playerID == playerID {
                detail.exposedKong += kong.exposedKongCount
                detail.concealedKong += kong.concealedKongCount
            }

            let deltas = roundScoreDeltas(record: record, players: allPlayers)
            detail.scoreDelta += deltas[playerID] ?? 0
        }

        return detail
    }

    func groupRecordsByDay(records: [RoundRecord]) -> [(date: Date, records: [RoundRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (date: $0.key, records: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 当日与本场盈亏

    func getTodayScoreDelta(for player: Player, context: ModelContext) -> Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return 0 }

        let descriptor = FetchDescriptor<RoundRecord>(
            predicate: #Predicate<RoundRecord> { record in
                record.timestamp >= startOfToday && record.timestamp < startOfNextDay
            }
        )

        guard let todayRecords = try? context.fetch(descriptor) else { return 0 }
        let sortedByTime = todayRecords.sorted { $0.timestamp < $1.timestamp }
        
        let descriptorP = FetchDescriptor<Player>()
        let allPlayers = (try? context.fetch(descriptorP)) ?? []

        let playerID = player.id
        let playerName = player.name

        func involvesPlayer(_ record: RoundRecord) -> Bool {
            if record.isAdjustment {
                return record.adjustments.contains { $0.playerName.trimmingCharacters(in: .whitespaces) == playerName.trimmingCharacters(in: .whitespaces) }
            }
            var involvedIDs: Set<UUID> = [record.winnerID, record.dealerID]
            if let lid = record.loserID { involvedIDs.insert(lid) }
            for k in record.kongDetails { involvedIDs.insert(k.playerID) }
            return involvedIDs.contains(playerID)
        }

        let lastAdjustmentIndex = sortedByTime.lastIndex(where: { $0.isAdjustment && involvesPlayer($0) })
        let startIndex = lastAdjustmentIndex.map { $0 + 1 } ?? 0
        guard startIndex < sortedByTime.count else { return 0 }

        var totalDelta = 0
        for i in startIndex ..< sortedByTime.count {
            let record = sortedByTime[i]
            guard !record.isAdjustment else { continue }
            guard involvesPlayer(record) else { continue }

            let deltas = roundScoreDeltas(record: record, players: allPlayers)
            totalDelta += deltas[playerID] ?? 0
        }
        return totalDelta
    }

    func getSessionScoreDelta(for player: Player, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<RoundRecord>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        guard let allRecords = try? context.fetch(descriptor) else { return 0 }
        let lastAdjustmentIndex = allRecords.lastIndex(where: { $0.isAdjustment })
        let startIndex = lastAdjustmentIndex.map { $0 + 1 } ?? 0
        guard startIndex < allRecords.count else { return 0 }
        
        let descriptorP = FetchDescriptor<Player>()
        let allPlayers = (try? context.fetch(descriptorP)) ?? []

        let playerID = player.id
        var totalDelta = 0
        for i in startIndex ..< allRecords.count {
            let record = allRecords[i]
            guard !record.isAdjustment else { continue }

            let deltas = roundScoreDeltas(record: record, players: allPlayers)
            totalDelta += deltas[playerID] ?? 0
        }
        return totalDelta
    }

    // MARK: - CSV 引擎

    enum ImportMode {
        case append
        case overwrite
    }

    enum ImportResult {
        case success
        case formatError(reason: String)
    }

    func exportCSV(records: [RoundRecord], players: [Player]) -> String {
        let header = "Type,Timestamp,RoundNumber,DealerName,WinnerName,LoserName,IsSelfDrawn,Kongs,Adjustments"
        let idToName: [UUID: String] = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var rows: [String] = [header]
        for record in records {
            let timeStr = dateFormatter.string(from: record.timestamp)
            let roundStr = "\(record.roundNumber)"

            if record.isAdjustment {
                let adjustmentsStr = record.adjustments.map { "\($0.playerName):\($0.delta)" }.joined(separator: "|")
                let fields = [
                    escapeCSVField("Adjustment"),
                    escapeCSVField(timeStr),
                    escapeCSVField(roundStr),
                    escapeCSVField(""),
                    escapeCSVField(""),
                    escapeCSVField(""),
                    escapeCSVField(""),
                    escapeCSVField(""),
                    escapeCSVField(adjustmentsStr)
                ]
                rows.append(fields.joined(separator: ","))
            } else {
                let dealerName = idToName[record.dealerID] ?? ""
                let winnerName = idToName[record.winnerID] ?? ""
                let loserName: String = record.isSelfDrawn ? "" : (record.loserID.flatMap { idToName[$0] } ?? "")
                let isSelfDrawnStr = record.isSelfDrawn ? "true" : "false"
                let kongsStr = record.kongDetails
                    .compactMap { k -> String? in
                        guard let name = idToName[k.playerID], !name.isEmpty else { return nil }
                        return "\(name):\(k.exposedKongCount):\(k.concealedKongCount)"
                    }
                    .joined(separator: "|")
                let fields = [
                    escapeCSVField("Normal"),
                    escapeCSVField(timeStr),
                    escapeCSVField(roundStr),
                    escapeCSVField(dealerName),
                    escapeCSVField(winnerName),
                    escapeCSVField(loserName),
                    escapeCSVField(isSelfDrawnStr),
                    escapeCSVField(kongsStr),
                    escapeCSVField("")
                ]
                rows.append(fields.joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    private func escapeCSVField(_ s: String) -> String {
        if s.contains(",") || s.contains("\n") || s.contains("\"") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private func parseCSVRows(_ csvString: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = csvString.startIndex

        func finishRow() {
            currentRow.append(currentField)
            currentField = ""
            rows.append(currentRow)
            currentRow = []
        }

        while i < csvString.endIndex {
            let c = csvString[i]

            if inQuotes {
                if c == "\"" {
                    let nextIdx = csvString.index(after: i)
                    if nextIdx < csvString.endIndex && csvString[nextIdx] == "\"" {
                        currentField.append("\"")
                        i = nextIdx
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
                i = csvString.index(after: i)
                continue
            }

            switch c {
            case "\"":
                inQuotes = true
                i = csvString.index(after: i)
            case ",":
                currentRow.append(currentField)
                currentField = ""
                i = csvString.index(after: i)
            case "\n":
                finishRow()
                i = csvString.index(after: i)
            case "\r":
                var nextIdx = csvString.index(after: i)
                if nextIdx < csvString.endIndex && csvString[nextIdx] == "\n" {
                    nextIdx = csvString.index(after: nextIdx)
                }
                finishRow()
                i = nextIdx
            default:
                currentField.append(c)
                i = csvString.index(after: i)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    private func parseAdjustments(_ s: String) -> [ScoreAdjustment] {
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var result: [ScoreAdjustment] = []
        for part in s.split(separator: "|", omittingEmptySubsequences: false) {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let name = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let deltaStr = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                if let delta = Int(deltaStr), !name.isEmpty {
                    result.append(ScoreAdjustment(playerName: name, delta: delta))
                }
            }
        }
        return result
    }

    private func parseKongs(_ s: String, nameToPlayer: (String) -> Player?) -> [KongDetail] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var result: [KongDetail] = []
        for part in trimmed.split(separator: "|", omittingEmptySubsequences: false) {
            let parts = part.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let exposed = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let concealed = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
            guard exposed > 0 || concealed > 0 else { continue }
            guard let player = nameToPlayer(name) else { continue }
            result.append(KongDetail(playerID: player.id, exposedKongCount: exposed, concealedKongCount: concealed))
        }
        return result
    }

    func importCSV(csvString: String, context: ModelContext, currentPlayers: [Player], mode: ImportMode) -> ImportResult {
        let rows = parseCSVRows(csvString)
        guard rows.count >= 2 else {
            return .formatError(reason: "缺少表头或数据行，请使用本应用导出的 CSV 格式")
        }
        let headerRow = rows[0]
        guard headerRow.count >= 9 else {
            return .formatError(reason: "表头列数不足，应为 9 列")
        }
        let dataRows = Array(rows.dropFirst())

        for (index, row) in dataRows.enumerated() {
            guard row.count >= 9 else {
                return .formatError(reason: "第 \(index + 2) 行列数不足（需 9 列）")
            }
            func col(_ i: Int) -> String {
                row.indices.contains(i) ? row[i].trimmingCharacters(in: .whitespaces) : ""
            }
            let typeRaw = col(0).lowercased()
            let roundNumStr = col(2)
            let dealerName = col(3)
            let winnerName = col(4)
            let adjustmentsStr = col(8)

            guard typeRaw == "normal" || typeRaw == "adjustment" else {
                return .formatError(reason: "第 \(index + 2) 行 Type 必须为 Normal 或 Adjustment")
            }
            guard let _ = Int(roundNumStr) else {
                return .formatError(reason: "第 \(index + 2) 行局号必须为数字")
            }

            if typeRaw == "adjustment" {
                let adjustments = parseAdjustments(adjustmentsStr)
                guard !adjustments.isEmpty else {
                    return .formatError(reason: "第 \(index + 2) 行平账局 Adjustments 不能为空")
                }
            } else {
                guard !dealerName.isEmpty else {
                    return .formatError(reason: "第 \(index + 2) 行普通局庄家名不能为空")
                }
                guard !winnerName.isEmpty else {
                    return .formatError(reason: "第 \(index + 2) 行普通局赢家名不能为空")
                }
            }
        }

        var nameToPlayer: [String: Player] = [:]
        for p in currentPlayers {
            let key = p.name.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && nameToPlayer[key] == nil {
                nameToPlayer[key] = p
            }
        }
        func resolveOrCreatePlayer(_ name: String) -> Player? {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let p = nameToPlayer[trimmed] { return p }
            let newPlayer = Player(name: trimmed, avatarIcon: "person.circle.fill")
            context.insert(newPlayer)
            nameToPlayer[trimmed] = newPlayer
            return newPlayer
        }

        if mode == .overwrite {
            let descriptor = FetchDescriptor<RoundRecord>()
            if let allRecords = try? context.fetch(descriptor) {
                for r in allRecords {
                    context.delete(r)
                }
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for row in dataRows where nameToPlayer.isEmpty {
            guard row.count >= 9 else { continue }
            let typeRaw = row.indices.contains(0) ? row[0].trimmingCharacters(in: .whitespaces).lowercased() : ""
            if typeRaw == "adjustment" {
                let adjustments = parseAdjustments(row.indices.contains(8) ? row[8] : "")
                for adj in adjustments { _ = resolveOrCreatePlayer(adj.playerName) }
            } else {
                let dealerName = row.indices.contains(3) ? row[3].trimmingCharacters(in: .whitespaces) : ""
                let winnerName = row.indices.contains(4) ? row[4].trimmingCharacters(in: .whitespaces) : ""
                _ = resolveOrCreatePlayer(dealerName)
                _ = resolveOrCreatePlayer(winnerName)
            }
            if !nameToPlayer.isEmpty { break }
        }
        guard nameToPlayer.values.first != nil else {
            return .formatError(reason: "未能解析出任何有效玩家名，请检查数据")
        }
        let firstPlayer = nameToPlayer.values.first!
        let placeholderID = firstPlayer.id

        let session = GameSession(currentDealerID: placeholderID)
        session.players = Array(nameToPlayer.values)
        context.insert(session)

        for row in dataRows {
            guard row.count >= 9 else { continue }

            func col(_ i: Int) -> String {
                row.indices.contains(i) ? row[i].trimmingCharacters(in: .whitespaces) : ""
            }

            let typeRaw = col(0)
            let timeStr = col(1)
            let roundNumStr = col(2)
            let dealerName = col(3)
            let winnerName = col(4)
            let loserName = col(5)
            let isSelfDrawnStr = col(6)
            let kongsStr = col(7)
            let adjustmentsStr = col(8)

            guard let roundNum = Int(roundNumStr) else { continue }

            var timestamp = Date()
            if !timeStr.isEmpty, let d = dateFormatter.date(from: timeStr) {
                timestamp = d
            }

            if typeRaw.lowercased() == "adjustment" {
                let adjustments = parseAdjustments(adjustmentsStr)
                guard !adjustments.isEmpty else { continue }
                for adj in adjustments { _ = resolveOrCreatePlayer(adj.playerName) }
                let placeholder = nameToPlayer.values.first ?? firstPlayer
                let record = RoundRecord(
                    timestamp: timestamp,
                    roundNumber: roundNum,
                    winnerID: placeholder.id,
                    loserID: nil,
                    isSelfDrawn: false,
                    kongDetails: [],
                    gameSession: session,
                    dealerID: placeholder.id,
                    isAdjustment: true,
                    adjustments: adjustments
                )
                context.insert(record)
                record.gameSession = session
                session.roundRecords.append(record)
            } else {
                guard let dealer = resolveOrCreatePlayer(dealerName),
                      let winner = resolveOrCreatePlayer(winnerName) else { continue }
                let loser = loserName.isEmpty ? nil : resolveOrCreatePlayer(loserName)
                let isSelfDrawn = isSelfDrawnStr.lowercased() == "true"
                let kongDetails = parseKongs(kongsStr, nameToPlayer: resolveOrCreatePlayer)
                let record = RoundRecord(
                    timestamp: timestamp,
                    roundNumber: roundNum,
                    winnerID: winner.id,
                    loserID: loser?.id,
                    isSelfDrawn: isSelfDrawn,
                    kongDetails: kongDetails,
                    gameSession: session,
                    dealerID: dealer.id
                )
                context.insert(record)
                record.gameSession = session
                session.roundRecords.append(record)
            }
        }

        session.players = Array(nameToPlayer.values)
        try? context.save()
        return .success
    }
}