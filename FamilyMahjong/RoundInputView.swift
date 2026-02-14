//
//  RoundInputView.swift
//  FamilyMahjong
//
//  本局结算页占位，后续接计分/结算 UI。
//

import SwiftUI
import SwiftData

struct RoundInputView: View {
    let session: GameSession

    var body: some View {
        Text("结算页待开发")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 248/255, green: 249/255, blue: 250/255))
            .navigationTitle("本局结算")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RoundInputView(session: GameSession(currentDealerID: UUID()))
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
