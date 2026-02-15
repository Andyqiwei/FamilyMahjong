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

/// 算分引擎：负责单局结算与撤销，RoundRecord 为唯一真相，统计由遍历 RoundRecord 实时计算。不持有 ModelContext，由调用方在合适 context 中保存。
final class ScoringViewModel: ObservableObject {

    // MARK: - 只读计算（本局）

    /// 只读计算本局每人得分变化（不修改 Player）。用于结果页展示。
    /// 返回 [playerID: 本局得分变化]，赢为正、输为负。
    func roundScoreDeltas(record: RoundRecord, players: [Player]) -> [UUID: Int] {
        var deltas: [UUID: Int] = [:]
        for p in players { deltas[p.id] = 0 }

        if record.isAdjustment {
            for adj in record.adjustments {
                if let p = players.first(where: { $0.name == adj.playerName }) {
                    deltas[p.id, default: 0] += adj.delta
                }
            }
            return deltas
        }

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
        if record.isAdjustment { return [] }
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
    @discardableResult
    func calculateAndApplyRound(
        session: GameSession,
        roundNumber: Int,
        winnerID: UUID,
        loserID: UUID?,
        isSelfDrawn: Bool,
        kongs: [KongDetail]
    ) -> RoundRecord? { // 👈 增加返回值类型
        let players = session.players
        guard players.count == 4 else { return nil }
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
        
        return newRecord // 👈 必须把刚建好的记录抛出去
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
        // 编辑时保留原 timestamp，避免 log 中局序错乱
    }

    // MARK: - 全局统计（遍历 RoundRecord 实时计算）

    /// 所有涉及该玩家的 RoundRecord（赢家、点炮或杠牌参与）。
    private func recordsInvolving(player: Player, context: ModelContext) -> [RoundRecord] {
        let descriptor = FetchDescriptor<RoundRecord>()
        guard let allRecords = try? context.fetch(descriptor) else { return [] }
        let playerID = player.id
        return allRecords.filter { record in
            if record.isAdjustment {
                return record.adjustments.contains { $0.playerName == player.name }
            }
            return record.winnerID == playerID ||
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
            guard let players = record.gameSession?.players, !players.isEmpty else { continue }
            guard record.isAdjustment || players.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: players)
            total += deltas[playerID] ?? 0
        }
        return total
    }

    /// 该玩家总胡牌次数。
    func getWinCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.winnerID == player.id && !$0.isAdjustment }.count
    }

    /// 该玩家总点炮次数。
    func getLoseCount(for player: Player, context: ModelContext) -> Int {
        recordsInvolving(player: player, context: context).filter { $0.loserID == player.id && !$0.isAdjustment }.count
    }

    /// 该玩家总杠牌次数（明杠 + 暗杠）。
    func getTotalKongs(for player: Player, context: ModelContext) -> Int {
        let records = recordsInvolving(player: player, context: context).filter { !$0.isAdjustment }
        let playerID = player.id
        return records.reduce(0) { sum, record in
            let k = record.kongDetails.first { $0.playerID == playerID }
            return sum + (k.map { $0.exposedKongCount + $0.concealedKongCount } ?? 0)
        }
    }

    // MARK: - 聚合统计（用于详细报表）

    /// 对给定 records 聚合指定玩家的积分变动、胡/自摸/点炮/明杠/暗杠。
    /// 积分变动与胡/自摸/点炮/明杠/暗杠均仅统计普通局；平账不计入。当日变动 = 当天所有普通局的积分变动累加（平账前后的普通局都算）。
    func aggregateStats(for player: Player, in records: [RoundRecord], allPlayers: [Player]) -> PlayerStatDetail {
        var detail = PlayerStatDetail()
        let playerID = player.id

        for record in records {
            if record.isAdjustment { continue }

            let sessionPlayers = record.gameSession?.players ?? []
            guard sessionPlayers.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: sessionPlayers)
            detail.scoreDelta += deltas[playerID] ?? 0

            if record.winnerID == playerID {
                detail.win += 1
                if record.isSelfDrawn { detail.selfDrawn += 1 }
            }
            if record.loserID == playerID { detail.lose += 1 }

            for kong in record.kongDetails where kong.playerID == playerID {
                detail.exposedKong += kong.exposedKongCount
                detail.concealedKong += kong.concealedKongCount
            }
        }

        return detail
    }

    /// 按自然日分组，日期倒序（新日期在前）。
    func groupRecordsByDay(records: [RoundRecord]) -> [(date: Date, records: [RoundRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (date: $0.key, records: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 当日积分变动

    /// 查询该玩家在今天参与的所有 RoundRecord，计算当日积分净变动（赢为正、输为负）。平账后只计平账之后的普通局，平账记录本身不计入。
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

        let playerID = player.id
        let playerName = player.name

        func involvesPlayer(_ record: RoundRecord) -> Bool {
            if record.isAdjustment {
                return record.adjustments.contains { $0.playerName == playerName }
            }
            return record.winnerID == playerID
                || record.loserID == playerID
                || record.kongDetails.contains { $0.playerID == playerID }
        }

        let lastAdjustmentIndex = sortedByTime.lastIndex(where: { $0.isAdjustment && involvesPlayer($0) })
        let startIndex: Int
        if let idx = lastAdjustmentIndex {
            startIndex = idx + 1
        } else {
            startIndex = 0
        }

        guard startIndex < sortedByTime.count else { return 0 }

        var totalDelta = 0
        for i in startIndex ..< sortedByTime.count {
            let record = sortedByTime[i]
            guard !record.isAdjustment else { continue }
            guard involvesPlayer(record) else { continue }
            guard let players = record.gameSession?.players, players.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: players)
            totalDelta += deltas[playerID] ?? 0
        }

        return totalDelta
    }

    // MARK: - 本场盈亏（从上次平账起到现在，仅普通局，供大厅展示）

    /// 从上次平账之后到现在的积分净变动（仅普通局，平账不计）。无平账则从最早记录起算。与「当日」「历史每日」无关，仅供大厅「本场盈亏」展示。
    func getSessionScoreDelta(for player: Player, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<RoundRecord>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        guard let allRecords = try? context.fetch(descriptor) else { return 0 }
        let lastAdjustmentIndex = allRecords.lastIndex(where: { $0.isAdjustment })
        let startIndex = lastAdjustmentIndex.map { $0 + 1 } ?? 0
        guard startIndex < allRecords.count else { return 0 }

        let playerID = player.id
        var totalDelta = 0
        for i in startIndex ..< allRecords.count {
            let record = allRecords[i]
            guard !record.isAdjustment else { continue }
            guard let players = record.gameSession?.players, players.count == 4 else { continue }
            let deltas = roundScoreDeltas(record: record, players: players)
            totalDelta += deltas[playerID] ?? 0
        }
        return totalDelta
    }

    // MARK: - CSV 引擎

    /// CSV 导入模式：追加或覆盖。
    enum ImportMode {
        case append
        case overwrite
    }

    /// CSV 导入结果：成功或格式错误。
    enum ImportResult {
        case success
        case formatError(reason: String)
    }

    /// 导出日志为 CSV 字符串。表头：Type,Timestamp,RoundNumber,DealerName,WinnerName,LoserName,IsSelfDrawn,Kongs,Adjustments。使用玩家名字，绝不出现 UUID。
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

    /// RFC 4180：字段含逗号、换行、双引号时用双引号包裹，内部双引号写作 ""。
    private func escapeCSVField(_ s: String) -> String {
        if s.contains(",") || s.contains("\n") || s.contains("\"") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// 解析 CSV 字符串为行（每行为字段数组）。支持引号内逗号、换行与 "" 转义。
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

    /// 解析平账明细字符串，格式 "name1:50|name2:-20"（用 | 分隔）。
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

    /// 解析杠牌字符串，格式 "name:明杠数:暗杠数|..."（用 | 分隔）。未找到的玩家名跳过。
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

    /// 导入 CSV：解析行，自动创建缺失玩家，根据 mode 覆盖或追加 RoundRecord，并关联 GameSession。
    /// 列顺序：Type, Timestamp, RoundNumber, DealerName, WinnerName, LoserName, IsSelfDrawn, Kongs, Adjustments
    /// 若格式有误则返回 .formatError，不会修改数据库；验证通过后才执行导入。
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

        var nameToPlayer: [String: Player] = Dictionary(uniqueKeysWithValues: currentPlayers.map { ($0.name, $0) })
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
