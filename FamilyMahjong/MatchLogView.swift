//
//  MatchLogView.swift
//  FamilyMahjong
//
//  历史日志与撤销：所有对局记录，点击编辑、左滑撤销。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（春节卡通风）

private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm"
    f.locale = Locale(identifier: "zh_CN")
    return f
}()

private let roundMmDdFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd"
    f.locale = Locale(identifier: "zh_CN")
    return f
}()

private extension Color {
    static let logRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let logGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let logBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
}

// MARK: - MatchLogView

struct MatchLogView: View {
    let records: [RoundRecord]
    let scoringViewModel: ScoringViewModel
    var onPopToRoot: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var saveErrorMessage: String?
    @State private var showSaveErrorAlert = false

    init(records: [RoundRecord], scoringViewModel: ScoringViewModel, onPopToRoot: (() -> Void)? = nil) {
        self.records = records
        self.scoringViewModel = scoringViewModel
        self.onPopToRoot = onPopToRoot
    }

    init(gameSession: GameSession, scoringViewModel: ScoringViewModel, onPopToRoot: (() -> Void)? = nil) {
        self.records = gameSession.roundRecords
        self.scoringViewModel = scoringViewModel
        self.onPopToRoot = onPopToRoot
    }

    private var sortedRecords: [RoundRecord] {
        records.sorted { $0.timestamp > $1.timestamp }
    }

    private func playerName(record: RoundRecord, id: UUID) -> String {
        record.gameSession?.players.first { $0.id == id }?.name ?? "未知"
    }

    private func kongSummary(for record: RoundRecord) -> String {
        guard !record.kongDetails.isEmpty else { return "无" }
        let parts = record.kongDetails.compactMap { k -> String? in
            let name = playerName(record: record, id: k.playerID)
            var s: [String] = []
            if k.exposedKongCount > 0 { s.append("\(k.exposedKongCount)明") }
            if k.concealedKongCount > 0 { s.append("\(k.concealedKongCount)暗") }
            guard !s.isEmpty else { return nil }
            return "\(name) \(s.joined(separator: ""))"
        }
        return parts.joined(separator: "、")
    }

    private func deleteRecords(at indexSet: IndexSet) {
        let sorted = sortedRecords
        // 若有记录的 gameSession 为 nil，无法正确撤销分数，不执行删除并提示
        for index in indexSet {
            guard index < sorted.count else { continue }
            let record = sorted[index]
            if record.gameSession == nil {
                saveErrorMessage = "该记录关联的牌局已丢失，无法撤销分数"
                showSaveErrorAlert = true
                return
            }
        }
        for index in indexSet {
            guard index < sorted.count else { continue }
            let record = sorted[index]
            guard let session = record.gameSession else { continue }
            scoringViewModel.undoRound(record: record, session: session)
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "保存失败：\(error.localizedDescription)"
            showSaveErrorAlert = true
        }
    }

    var body: some View {
        ZStack {
            Color.logBackground
                .ignoresSafeArea()

            if sortedRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Color.logGold)
                    Text("暂无对局记录")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedRecords, id: \.id) { record in
                        Group {
                            if let session = record.gameSession {
                                NavigationLink {
                                    RoundInputView(
                                        gameSession: session,
                                        viewModel: scoringViewModel,
                                        editingRecord: record,
                                        onDismissToLobby: nil
                                    )
                                } label: {
                                    logRow(record: record)
                                }
                            } else {
                                logRow(record: record)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        )
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteRecords)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("历史日志")
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
                        .foregroundStyle(Color.logRed)
                }
            }
        }
        .alert("提示", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            if let msg = saveErrorMessage {
                Text(msg)
            }
        }
    }

    private func logRow(record: RoundRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(roundMmDdFormatter.string(from: record.timestamp)) 第\(record.roundNumber)局")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.logRed)
                Spacer()
                Text(logDateFormatter.string(from: record.timestamp))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "star.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.logGold)
                Text("\(playerName(record: record, id: record.winnerID)) 胡")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 4) {
                Image(systemName: record.isSelfDrawn ? "hand.raised.fill" : "flame.fill")
                    .font(.caption)
                    .foregroundStyle(record.isSelfDrawn ? Color.logGold : Color.logRed)
                Text(record.isSelfDrawn ? "自摸" : "\(record.loserID.map { playerName(record: record, id: $0) } ?? "?") 点炮")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("杠：\(kongSummary(for: record))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
    let record = RoundRecord(
        roundNumber: 1,
        winnerID: session.players[0].id,
        loserID: session.players[1].id,
        isSelfDrawn: false,
        kongDetails: [],
        gameSession: session,
        dealerID: session.currentDealerID
    )
    session.roundRecords.append(record)
    return NavigationStack {
        MatchLogView(gameSession: session, scoringViewModel: ScoringViewModel())
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
