//
//  LobbyView.swift
//  FamilyMahjong
//
//  家庭麻将馆大厅：玩家网格、选中组局、添加新家人、开始本局。
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - 主题色（春节卡通 Q 弹感）

private extension Color {
    static let lobbyRed = Color(red: 230/255, green: 57/255, blue: 70/255)      // #E63946
    static let lobbyGold = Color(red: 233/255, green: 196/255, blue: 106/255)   // #E9C46A
    static let lobbyGoldDark = Color(red: 244/255, green: 162/255, blue: 97/255) // #F4A261
    static let lobbyBackground = Color(red: 248/255, green: 249/255, blue: 250/255) // #F8F9FA
}

// MARK: - LobbyView

struct LobbyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @StateObject private var scoringViewModel = ScoringViewModel()

    @State private var selectedPlayerIDs: Set<UUID> = []
    @State private var showAddPlayerSheet = false
    @State private var editingPlayer: Player?
    @State private var playersToTable: [Player]?
    @State private var navigateToTable = false

    private var selectedFour: [Player] {
        let ordered = players.filter { selectedPlayerIDs.contains($0.id) }
        return Array(ordered.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        titleBar
                        playerGrid
                        Spacer(minLength: 120)
                    }
                    .background(Color.lobbyBackground)
                }
                .background(Color.lobbyBackground)

                // 底部按钮区置于最上层，避免被 ScrollView 手势或层级遮挡（iOS 17 点击无反应时多为层级/命中问题）
                VStack(spacing: 12) {
                    if selectedPlayerIDs.count == 4 {
                        startGameButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    addPlayerButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .zIndex(1)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToTable) {
                if let list = playersToTable, list.count == 4 {
                    GameTableView(players: list, onDismissToLobby: { navigateToTable = false })
                }
            }
            .sheet(isPresented: $showAddPlayerSheet) {
                AddPlayerSheet(editingPlayer: editingPlayer, existingPlayers: players, onSave: { name, avatarData in
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let editing = editingPlayer {
                        editing.name = trimmedName
                        editing.avatarData = avatarData
                        try? modelContext.save()
                    } else {
                        let player = Player(
                            name: trimmedName,
                            avatarIcon: "person.circle.fill",
                            avatarData: avatarData
                        )
                        modelContext.insert(player)
                    }
                    showAddPlayerSheet = false
                })
            }
            .onChange(of: showAddPlayerSheet) { _, isShowing in
                if !isShowing { editingPlayer = nil }
            }
        }
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        VStack(spacing: 0) {
            // 顶层：图标按钮独立占一行，不与标题重叠
            HStack {
                NavigationLink(destination: DataManagementView()) {
                    Label("设置", systemImage: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.lobbyRed)
                }
                Spacer()
                HStack(spacing: 16) {
                    NavigationLink(destination: RecentMatchLogWrapperView()) {
                        Image(systemName: "doc.text")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.lobbyRed)
                    }
                    NavigationLink(destination: ScoreAdjustmentWrapperView()) {
                        Image(systemName: "equal.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.lobbyRed)
                    }
                    NavigationLink(destination: StatsView()) {
                        Image(systemName: "chart.bar")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.lobbyRed)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 下层：标题居中，与按钮完全分离
            VStack(spacing: 4) {
                Text("2802老朱家麻将馆")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.lobbyRed)
                Text(Date().festiveDateString())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("今天谁上桌？")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .background(Color.lobbyBackground)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - 玩家网格

    private var playerGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(players, id: \.id) { player in
                PlayerCardView(
                    player: player,
                    isSelected: selectedPlayerIDs.contains(player.id),
                    scoringViewModel: scoringViewModel,
                    onTap: { toggleSelection(player.id) },
                    onEdit: {
                        editingPlayer = player
                        showAddPlayerSheet = true
                    },
                    onDelete: {
                        modelContext.delete(player)
                        try? modelContext.save()
                    }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedPlayerIDs.contains(id) {
            selectedPlayerIDs.remove(id)
        } else if selectedPlayerIDs.count < 4 {
            selectedPlayerIDs.insert(id)
        }
    }

    // MARK: - 开始本局按钮

    private var startGameButton: some View {
        Button {
            startGame()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("开始本局")
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Rectangle()) // iOS 17：让整块区域参与命中测试，避免只有图标/文字可点
            .background(
                LinearGradient(
                    colors: [Color.lobbyRed, Color.lobbyRed.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.2), value: selectedPlayerIDs.count)
    }

    private func startGame() {
        guard selectedFour.count == 4 else { return }
        playersToTable = selectedFour
        navigateToTable = true
    }

    // MARK: - 添加新家人按钮

    private var addPlayerButton: some View {
        Button {
            editingPlayer = nil
            showAddPlayerSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("添加新家人")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.lobbyRed, Color.lobbyRed.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 8, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 分数平账包装（大厅入口）

struct ScoreAdjustmentWrapperView: View {
    @Query(sort: \Player.name) private var players: [Player]
    @Environment(\.modelContext) private var modelContext
    private var scoringViewModel = ScoringViewModel()

    var body: some View {
        ScoreAdjustmentView(players: players, scoringViewModel: scoringViewModel)
            .navigationTitle("分数平账 / 初始化")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 战绩日志包装（大厅入口：最近牌局或空状态）

struct RecentMatchLogWrapperView: View {
    var onPopToRoot: (() -> Void)? = nil

    init(onPopToRoot: (() -> Void)? = nil) {
        self.onPopToRoot = onPopToRoot
    }

    @Query(sort: \RoundRecord.timestamp, order: .reverse) private var recentRecords: [RoundRecord]
    private var scoringViewModel = ScoringViewModel()

    var body: some View {
        Group {
            if recentRecords.isEmpty {
                ZStack {
                    Color.lobbyBackground
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(Color.lobbyGold)
                        Text("暂无牌局记录")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MatchLogView(records: recentRecords, scoringViewModel: scoringViewModel, onPopToRoot: onPopToRoot)
            }
        }
        .navigationTitle("战绩日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 玩家卡片

private struct PlayerCardView: View {
    let player: Player
    let isSelected: Bool
    let scoringViewModel: ScoringViewModel
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext

    private var sessionDelta: Int {
        scoringViewModel.getSessionScoreDelta(for: player, context: modelContext)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PlayerAvatarView(player: player, size: 64, iconColor: Color.lobbyRed)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.lobbyGold)
                            .background(.white, in: Circle())
                    }
                }
                Text(player.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("总积分 \(scoringViewModel.getTotalScore(for: player, context: modelContext))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if sessionDelta != 0 {
                    Text(sessionDelta > 0 ? "本场盈亏 +\(sessionDelta)" : "本场盈亏 \(sessionDelta)")
                        .font(.caption2)
                        .foregroundStyle(sessionDelta > 0 ? Color.green : Color.red)
                } else {
                    Text("本场盈亏 0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.lobbyGold : Color.clear, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.08), radius: 5, y: 3)
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("编辑家人信息", systemImage: "pencil")
            }
            Button("删除家人", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - 添加新家人 Sheet

private struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showDuplicateNameAlert = false
    var editingPlayer: Player?
    let existingPlayers: [Player]
    let onSave: (String, Data?) -> Void

    private var otherPlayersForNameCheck: [Player] {
        guard let editing = editingPlayer else { return existingPlayers }
        return existingPlayers.filter { $0.id != editing.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $name)
                        .textContentType(.name)
                } header: {
                    Text(editingPlayer == nil ? "新家人" : "家人信息")
                }
                Section {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 12) {
                            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(Color.lobbyRed.opacity(0.6))
                            }
                            Text("选一张头像")
                                .foregroundStyle(.primary)
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            guard let newItem else {
                                selectedImageData = nil
                                return
                            }
                            if let data = try? await newItem.loadTransferable(type: Data.self) {
                                selectedImageData = compressImageData(data)
                            } else {
                                selectedImageData = nil
                            }
                        }
                    }
                } header: {
                    Text("头像")
                }
            }
            .navigationTitle(editingPlayer == nil ? "添加新家人" : "编辑家人信息")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let editing = editingPlayer {
                    name = editing.name
                    selectedImageData = editing.avatarData
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        if otherPlayersForNameCheck.contains(where: { $0.name == trimmedName }) {
                            showDuplicateNameAlert = true
                            return
                        }
                        onSave(trimmedName, selectedImageData)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("名字已存在", isPresented: $showDuplicateNameAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("名字已存在，请加个后缀区分（如：大舅2）")
            }
        }
    }

    private func compressImageData(_ data: Data) -> Data? {
        guard let uiImage = UIImage(data: data) else { return data }
        return uiImage.jpegData(compressionQuality: 0.6)
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
    LobbyView()
        .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
