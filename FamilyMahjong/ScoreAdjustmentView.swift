//
//  ScoreAdjustmentView.swift
//  FamilyMahjong
//
//  分数初始化 / 手动平账：按目标分数录入，生成一条 isAdjustment 的 RoundRecord。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（春节卡通风）

private extension Color {
    static let adjRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let adjGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let adjBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
}

// MARK: - ScoreAdjustmentView

struct ScoreAdjustmentView: View {
    let players: [Player]
    let scoringViewModel: ScoringViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var targetScoreStrings: [UUID: String] = [:]
    @State private var saveErrorMessage: String?
    @State private var showSaveErrorAlert = false

    private func currentScore(for player: Player) -> Int {
        scoringViewModel.getTotalScore(for: player, context: modelContext)
    }

    private func targetScore(for player: Player) -> Int {
        let s = targetScoreStrings[player.id] ?? ""
        return Int(s.trimmingCharacters(in: .whitespaces)) ?? currentScore(for: player)
    }

    private func confirmAdjustment() {
        guard !players.isEmpty else { return }

        var adjustments: [ScoreAdjustment] = []
        for player in players {
            let current = currentScore(for: player)
            let target = targetScore(for: player)
            let delta = target - current
            if delta != 0 {
                adjustments.append(ScoreAdjustment(playerName: player.name, delta: delta))
            }
        }

        if adjustments.isEmpty {
            saveErrorMessage = "所有玩家目标分数与当前一致，无需平账"
            showSaveErrorAlert = true
            return
        }

        let placeholderID = players[0].id
        let roundNumber = scoringViewModel.getNextRoundNumberForToday(context: modelContext)

        let session = GameSession(currentDealerID: placeholderID)
        session.players = players
        modelContext.insert(session)

        let record = RoundRecord(
            roundNumber: roundNumber,
            winnerID: placeholderID,
            loserID: nil,
            isSelfDrawn: false,
            kongDetails: [],
            gameSession: session,
            dealerID: placeholderID,
            isAdjustment: true,
            adjustments: adjustments
        )
        modelContext.insert(record)
        record.gameSession = session
        session.roundRecords.append(record)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "保存失败：\(error.localizedDescription)"
            showSaveErrorAlert = true
        }
    }

    var body: some View {
        ZStack {
            Color.adjBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("输入每人目标分数，确认后将按差值写入一条平账记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    ForEach(players, id: \.id) { player in
                        HStack(spacing: 12) {
                            Text(player.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.adjRed)
                                .frame(width: 72, alignment: .leading)

                            Text("当前 \(currentScore(for: player))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("目标分数", text: Binding(
                                get: { targetScoreStrings[player.id] ?? "" },
                                set: { newValue in
                                    var copy = targetScoreStrings
                                    copy[player.id] = newValue
                                    targetScoreStrings = copy
                                }
                            ))
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        )
                    }
                    .padding(.horizontal, 20)

                    Button(action: confirmAdjustment) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("确认平账")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.adjRed)
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - ScaleButtonStyle（与 Lobby 一致）

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let players = [
        Player(name: "爸爸", avatarIcon: "person.circle.fill"),
        Player(name: "妈妈", avatarIcon: "person.circle.fill"),
        Player(name: "叔叔", avatarIcon: "person.circle.fill"),
        Player(name: "阿姨", avatarIcon: "person.circle.fill")
    ]
    return NavigationStack {
        ScoreAdjustmentView(players: players, scoringViewModel: ScoringViewModel())
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
