//
//  GameView.swift
//  FamilyMahjong
//
//  牌局页占位：接收 GameSession，显示本局进行中及玩家信息，便于后续接计分/牌局 UI。
//

import SwiftUI
import SwiftData

struct GameView: View {
    let session: GameSession
    @Environment(\.modelContext) private var modelContext
    @StateObject private var scoringViewModel = ScoringViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("本局进行中")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color(red: 230/255, green: 57/255, blue: 70/255))

                Text("已进行 \(session.roundRecords.count) 局")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.players.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(player.name)
                                .font(.headline)
                            Spacer()
                            Text("总积分 \(scoringViewModel.getTotalScore(for: player, context: modelContext))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 32)
        }
        .background(Color(red: 248/255, green: 249/255, blue: 250/255))
        .navigationTitle("牌局")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GameView(session: GameSession(currentDealerID: UUID()))
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
