//
//  LobbyView.swift
//  FamilyMahjong
//
//  家庭麻将馆大厅：玩家网格、选中组局、添加新雀友、开始本局。
//

import SwiftUI
import SwiftData

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

    @State private var selectedPlayerIDs: Set<UUID> = []
    @State private var showAddPlayerSheet = false
    @State private var playersToTable: [Player]?
    @State private var navigateToTable = false

    private var selectedFour: [Player] {
        let ordered = players.filter { selectedPlayerIDs.contains($0.id) }
        return Array(ordered.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 程序化跳转到选庄页 GameTableView（隐藏的 NavigationLink）
                if let list = playersToTable, list.count == 4 {
                    NavigationLink(destination: GameTableView(players: list), isActive: $navigateToTable) {
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .hidden()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        titleBar
                        playerGrid
                        Spacer(minLength: 120)
                    }
                    .background(Color.lobbyBackground)
                }
                .background(Color.lobbyBackground)

                VStack(spacing: 12) {
                    if selectedPlayerIDs.count == 4 {
                        startGameButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    addPlayerButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddPlayerSheet) {
                AddPlayerSheet(onSave: { name in
                    let player = Player(name: name.trimmingCharacters(in: .whitespacesAndNewlines), avatarIcon: "person.circle.fill")
                    modelContext.insert(player)
                    showAddPlayerSheet = false
                })
            }
        }
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        VStack(spacing: 4) {
            Text("家庭麻将馆")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.lobbyRed)
            Text("今天谁上桌？")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
                    onTap: { toggleSelection(player.id) }
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

    // MARK: - 添加新雀友按钮

    private var addPlayerButton: some View {
        Button {
            showAddPlayerSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("添加新雀友")
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

// MARK: - 玩家卡片

private struct PlayerCardView: View {
    let player: Player
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.lobbyGold.opacity(0.4), Color.lobbyGoldDark.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: player.avatarIcon)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Color.lobbyRed)
                        )
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
                Text("总积分 \(player.totalScore)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }
}

// MARK: - 添加新雀友 Sheet

private struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $name)
                        .textContentType(.name)
                } header: {
                    Text("新雀友")
                }
            }
            .navigationTitle("添加新雀友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSave(name)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
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
    LobbyView()
        .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
