//
//  RoundInputView.swift
//  FamilyMahjong
//
//  单局结算录入页：谁胡了、自摸/点炮、杠牌登记、确认算分。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（春节卡通风）

private extension Color {
    static let inputRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let inputGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let inputBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
}

// MARK: - RoundInputView

struct RoundInputView: View {
    let gameSession: GameSession
    let viewModel: ScoringViewModel
    var onDismissToLobby: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedWinner: Player?
    @State private var isSelfDrawn = false
    @State private var selectedLoser: Player?
    @State private var kongDetails: [UUID: KongDetail] = [:]
    @State private var showScoreResult = false
    @State private var popToTableAfterResult = false

    private var roundNumber: Int {
        gameSession.roundRecords.count + 1
    }

    private var canConfirm: Bool {
        guard selectedWinner != nil else { return false }
        if isSelfDrawn { return true }
        return selectedLoser != nil
    }

    private var losersCandidates: [Player] {
        guard let winner = selectedWinner else { return gameSession.players }
        return gameSession.players.filter { $0.id != winner.id }
    }

    var body: some View {
        ZStack {
            Color.inputBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    whoWonCard
                    if !isSelfDrawn {
                        whoChuckedCard
                    }
                    exposedKongsCard
                    concealedKongsCard
                    confirmButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .animation(.easeInOut(duration: 0.25), value: isSelfDrawn)
            .background(
                NavigationLink(
                    destination: ScoreResultView(
                        gameSession: gameSession,
                        currentRecord: gameSession.roundRecords.last,
                        popToTableAfterResult: $popToTableAfterResult,
                        onDismissToLobby: onDismissToLobby,
                        scoringViewModel: viewModel
                    ),
                    isActive: $showScoreResult
                ) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .hidden()
            )
        }
        .onChange(of: popToTableAfterResult) { _, newValue in
            if newValue {
                selectedWinner = nil
                isSelfDrawn = false
                selectedLoser = nil
                kongDetails = [:]
                popToTableAfterResult = false
                dismiss()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("第 \(roundNumber) 局")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.inputRed)
                    Text("本局结算")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // 帮助占位
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.inputRed)
                }
            }
        }
    }

    // MARK: - 谁胡了

    private var whoWonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.inputGold)
                Text("谁胡了？")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("选一人")
                    .font(.caption)
                    .foregroundStyle(Color.inputRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.inputRed.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                ForEach(gameSession.players, id: \.id) { player in
                    winnerAvatarButton(player: player)
                }
            }

            Toggle(isOn: $isSelfDrawn) {
                Text("这是自摸")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(Color.inputGold)
            .onChange(of: isSelfDrawn) { _, new in
                if new { selectedLoser = nil }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private func winnerAvatarButton(player: Player) -> some View {
        let isSelected = selectedWinner?.id == player.id
        let isDealer = gameSession.currentDealerID == player.id
        return Button {
            selectedWinner = player
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.inputGold.opacity(0.5), Color.inputGold.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: player.avatarIcon)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color.inputRed)
                            )
                            .background(Color.white, in: Circle())
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.inputGold : Color.gray.opacity(0.3), lineWidth: isSelected ? 4 : 1.5)
                            )
                            .shadow(color: isSelected ? Color.inputGold.opacity(0.5) : .black.opacity(0.1), radius: isSelected ? 8 : 4, y: 2)
                    }
                    if isDealer {
                        Text("庄")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.inputGold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.inputGold.opacity(0.3), in: Capsule())
                            .overlay(Capsule().stroke(Color.inputRed, lineWidth: 1))
                            .offset(x: 4, y: -4)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.inputGold)
                            .background(.white, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                Text(player.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 谁点炮

    private var whoChuckedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color.inputRed)
                Text("谁点炮？")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 12) {
                ForEach(losersCandidates, id: \.id) { player in
                    loserAvatarButton(player: player)
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private func loserAvatarButton(player: Player) -> some View {
        let isSelected = selectedLoser?.id == player.id
        let isDealer = gameSession.currentDealerID == player.id
        return Button {
            selectedLoser = player
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.inputGold.opacity(0.4), Color.inputGold.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: player.avatarIcon)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.inputRed)
                        )
                        .background(Color.white, in: Circle())
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.primary : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1.5)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    if isDealer {
                        Text("庄")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.inputGold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.inputGold.opacity(0.3), in: Capsule())
                            .overlay(Capsule().stroke(Color.inputRed, lineWidth: 1))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(player.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 明杠

    private var exposedKongsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.inputRed)
                Text("明杠")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            ForEach(gameSession.players, id: \.id) { player in
                kongRow(player: player, kind: .exposed)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    // MARK: - 暗杠

    private var concealedKongsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.inputRed)
                Text("暗杠")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            ForEach(gameSession.players, id: \.id) { player in
                kongRow(player: player, kind: .concealed)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private enum KongKind {
        case exposed, concealed
    }

    private func kongRow(player: Player, kind: KongKind) -> some View {
        let value: Int = {
            let k = kongDetails[player.id]
            switch kind {
            case .exposed: return k?.exposedKongCount ?? 0
            case .concealed: return k?.concealedKongCount ?? 0
            }
        }()
        let binding: Binding<Int> = Binding(
            get: {
                let k = kongDetails[player.id]
                switch kind {
                case .exposed: return k?.exposedKongCount ?? 0
                case .concealed: return k?.concealedKongCount ?? 0
                }
            },
            set: { newVal in
                let clamped = min(4, max(0, newVal))
                var k = kongDetails[player.id] ?? KongDetail(playerID: player.id, exposedKongCount: 0, concealedKongCount: 0)
                switch kind {
                case .exposed: k.exposedKongCount = clamped
                case .concealed: k.concealedKongCount = clamped
                }
                kongDetails[player.id] = k
            }
        )
        return HStack(spacing: 12) {
            Circle()
                .fill(Color.inputGold.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: player.avatarIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.inputRed)
                )
            Text(player.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    binding.wrappedValue = value - 1
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value > 0 ? Color.inputRed : Color.gray.opacity(0.5))
                }
                .disabled(value <= 0)
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.inputRed)
                    .frame(minWidth: 28, alignment: .center)
                Button {
                    binding.wrappedValue = value + 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value < 4 ? Color.inputRed : Color.gray.opacity(0.5))
                }
                .disabled(value >= 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 确认算分

    private var confirmButton: some View {
        Button {
            confirmScore()
        } label: {
            HStack(spacing: 8) {
                Text("确认算分")
                    .font(.title3.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color.inputRed, Color.inputRed.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .disabled(!canConfirm)
        .opacity(canConfirm ? 1 : 0.5)
        .buttonStyle(ScaleButtonStyle())
    }

    private func confirmScore() {
        guard canConfirm, let winner = selectedWinner else { return }
        let kongsArray: [KongDetail] = gameSession.players.map { player in
            kongDetails[player.id] ?? KongDetail(playerID: player.id, exposedKongCount: 0, concealedKongCount: 0)
        }
        viewModel.calculateAndApplyRound(
            session: gameSession,
            winnerID: winner.id,
            loserID: isSelfDrawn ? nil : selectedLoser?.id,
            isSelfDrawn: isSelfDrawn,
            kongs: kongsArray
        )
        try? modelContext.save()
        showScoreResult = true
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
        RoundInputView(gameSession: session, viewModel: ScoringViewModel())
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
