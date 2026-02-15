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

private let roundMmDdFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd"
    f.locale = Locale(identifier: "zh_CN")
    return f
}()

private func roundDisplayText(date: Date, roundNumber: Int) -> String {
    "\(roundMmDdFormatter.string(from: date)) 第\(roundNumber)局"
}

// MARK: - RoundInputView

struct RoundInputView: View {
    let gameSession: GameSession
    let viewModel: ScoringViewModel
    var editingRecord: RoundRecord? = nil
    /// 由选庄页传入时，「原班人马」直接回到选庄页，跳过本结算页
    var onPopToTable: (() -> Void)? = nil
    var onDismissToLobby: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedWinner: Player?
    @State private var isSelfDrawn = false
    @State private var selectedLoser: Player?
    @State private var kongDetails: [UUID: KongDetail] = [:]
    @State private var showScoreResult = false
    @State private var popToTableAfterResult = false
    @State private var justCreatedRecord: RoundRecord? = nil
    @State private var saveErrorMessage: String?
    @State private var showSaveErrorAlert = false

    /// 编辑模式：来自历史日志的 editingRecord，或刚确认算分后从结果页返回的 justCreatedRecord
    private var isEditMode: Bool { (editingRecord ?? justCreatedRecord) != nil }

    private var roundNumber: Int {
        if let rec = justCreatedRecord ?? editingRecord { return rec.roundNumber }
        return viewModel.getNextRoundNumberForToday(context: modelContext)
    }

    private var canConfirm: Bool {
        guard selectedWinner != nil else { return false }
        if isSelfDrawn { return true }
        return selectedLoser != nil
    }

    /// 显示顺序：庄家第一，其余按姓名排序（各 tab 统一）
    private var playersInDisplayOrder: [Player] {
        let dealerID = gameSession.currentDealerID
        guard let dealer = gameSession.players.first(where: { $0.id == dealerID }) else {
            return gameSession.players.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        let others = gameSession.players
            .filter { $0.id != dealerID }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return [dealer] + others
    }

    private var losersCandidates: [Player] {
        guard let winner = selectedWinner else { return playersInDisplayOrder }
        return playersInDisplayOrder.filter { $0.id != winner.id }
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
                        // 🚀 核心修复：绝对不准用 .last，强绑定刚才生成的实例或编辑的实例！
                        currentRecord: justCreatedRecord ?? editingRecord,
                        popToTableAfterResult: $popToTableAfterResult,
                        onPopToTable: onPopToTable,
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
        .onAppear {
            if let rec = editingRecord {
                selectedWinner = gameSession.players.first { $0.id == rec.winnerID }
                isSelfDrawn = rec.isSelfDrawn
                selectedLoser = rec.loserID.flatMap { lid in gameSession.players.first { $0.id == lid } }
                var kongs: [UUID: KongDetail] = [:]
                for k in rec.kongDetails {
                    kongs[k.playerID] = k
                }
                kongDetails = kongs
            }
        }
        .onChange(of: popToTableAfterResult) { _, newValue in
            if newValue {
                selectedWinner = nil
                isSelfDrawn = false
                selectedLoser = nil
                kongDetails = [:]
                justCreatedRecord = nil
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
                    Text(roundDisplayText(
                        date: (justCreatedRecord ?? editingRecord)?.timestamp ?? Date(),
                        roundNumber: roundNumber
                    ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.inputRed)
                    Text(isEditMode ? "修改本局结算" : "本局结算")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
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
                ForEach(playersInDisplayOrder, id: \.id) { player in
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
                            PlayerAvatarView(player: player, size: 56, iconColor: Color.inputRed)
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
                    PlayerAvatarView(player: player, size: 56, iconColor: Color.inputRed)
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
            ForEach(playersInDisplayOrder, id: \.id) { player in
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
            ForEach(playersInDisplayOrder, id: \.id) { player in
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
            PlayerAvatarView(player: player, size: 40, iconColor: Color.inputRed)
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
                Text(isEditMode ? "确认修改" : "确认算分")
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
        let kongsArray: [KongDetail] = playersInDisplayOrder.map { player in
            kongDetails[player.id] ?? KongDetail(playerID: player.id, exposedKongCount: 0, concealedKongCount: 0)
        }
        
        if let rec = editingRecord {
            viewModel.updateRound(
                record: rec,
                session: gameSession,
                winnerID: winner.id,
                loserID: isSelfDrawn ? nil : selectedLoser?.id,
                isSelfDrawn: isSelfDrawn,
                kongs: kongsArray
            )
            do {
                try modelContext.save()
                dismiss()
            } catch {
                saveErrorMessage = "保存失败：\(error.localizedDescription)"
                showSaveErrorAlert = true
            }
        } else if let rec = justCreatedRecord {
            viewModel.updateRound(
                record: rec,
                session: gameSession,
                winnerID: winner.id,
                loserID: isSelfDrawn ? nil : selectedLoser?.id,
                isSelfDrawn: isSelfDrawn,
                kongs: kongsArray
            )
            do {
                try modelContext.save()
                showScoreResult = true
            } catch {
                saveErrorMessage = "保存失败：\(error.localizedDescription)"
                showSaveErrorAlert = true
            }
        } else {
            let currentRoundNum = self.roundNumber
            
            let newRecord = viewModel.calculateAndApplyRound(
                session: gameSession,
                roundNumber: currentRoundNum,
                winnerID: winner.id,
                loserID: isSelfDrawn ? nil : selectedLoser?.id,
                isSelfDrawn: isSelfDrawn,
                kongs: kongsArray
            )
            try? modelContext.save()
            
            justCreatedRecord = newRecord
            showScoreResult = true
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
        RoundInputView(gameSession: session, viewModel: ScoringViewModel())
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}