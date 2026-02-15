//
//  GameTableView.swift
//  FamilyMahjong
//
//  麻将桌与选庄页：接收 4 名 Player，选庄后创建 GameSession 并跳转结算页。
//

import SwiftUI
import SwiftData

// MARK: - 主题色（春节卡通风）

private extension Color {
    static let tableRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let tableGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let tableBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
    static let tableGreenLight = Color(red: 0.2, green: 0.65, blue: 0.35)
    static let tableGreenDark = Color(red: 0.15, green: 0.5, blue: 0.28)
}

// MARK: - GameTableView

struct GameTableView: View {
    let players: [Player]
    var onDismissToLobby: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @StateObject private var scoringViewModel = ScoringViewModel()
    @State private var selectedDealerID: UUID?
    @State private var sessionCreated: GameSession?
    @State private var navigateToRound = false
    @State private var isPlaying = false

    // 打牌动画用
    @State private var tileRotation: Double = 0
    @State private var diceRotation: Double = 0
    @State private var stackOffset: CGFloat = 0

    private let seatW: CGFloat = 80
    private let seatH: CGFloat = 100

    var body: some View {
        ZStack {
            Color.tableBackground
                .ignoresSafeArea()

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let centerX = width / 2
                let centerY = height / 2
                let tableSide = min(width, height) * 0.48
                let gap = min(width, height) * 0.06
                let seatHalfW = seatW / 2
                let seatHalfH = seatH / 2

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: width, height: height)

                    // 麻将桌（中心）
                    tableView(side: tableSide)
                        .position(x: centerX, y: centerY)

                    // 上 [0]
                    if players.count > 0 {
                        SeatView(
                            player: players[0],
                            isDealer: selectedDealerID == players[0].id,
                            onTap: { selectedDealerID = players[0].id }
                        )
                        .position(x: centerX, y: centerY - tableSide / 2 - gap - seatHalfH)
                    }

                    // 下 [1]
                    if players.count > 1 {
                        SeatView(
                            player: players[1],
                            isDealer: selectedDealerID == players[1].id,
                            onTap: { selectedDealerID = players[1].id }
                        )
                        .position(x: centerX, y: centerY + tableSide / 2 + gap + seatHalfH)
                    }

                    // 左 [2]
                    if players.count > 2 {
                        SeatView(
                            player: players[2],
                            isDealer: selectedDealerID == players[2].id,
                            onTap: { selectedDealerID = players[2].id }
                        )
                        .position(x: centerX - tableSide / 2 - gap - seatHalfW, y: centerY)
                    }

                    // 右 [3]
                    if players.count > 3 {
                        SeatView(
                            player: players[3],
                            isDealer: selectedDealerID == players[3].id,
                            onTap: { selectedDealerID = players[3].id }
                        )
                        .position(x: centerX + tableSide / 2 + gap + seatHalfW, y: centerY)
                    }

                    // 桌心：选庄时显示开始按钮，游戏中显示打牌动画
                    if isPlaying {
                        playingCenterUI
                            .position(x: centerX, y: centerY)
                    } else {
                        startButton
                            .position(x: centerX, y: centerY)
                    }
                }
                .frame(width: width, height: height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: navigateToRound) { _, newValue in
            if newValue == false {
                isPlaying = false
                selectedDealerID = nil
            }
        }
        .navigationTitle("选庄")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            Group {
                if let session = sessionCreated {
                    NavigationLink(
                        destination: RoundInputView(
                            gameSession: session,
                            viewModel: scoringViewModel,
                            onPopToTable: { navigateToRound = false },
                            onDismissToLobby: onDismissToLobby
                        ),
                        isActive: $navigateToRound
                    ) {
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .hidden()
                }
            }
        )
    }

    // MARK: - 麻将桌（绿色渐变 + 圆角 + 阴影）

    private func tableView(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 32)
            .fill(
                LinearGradient(
                    colors: [Color.tableGreenLight, Color.tableGreenDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    // MARK: - 开始本局按钮（桌心）

    private var startButton: some View {
        Button {
            startGame()
        } label: {
            Text("开始本局")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 160, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.tableRed, Color.tableRed.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 6, y: 3)
        }
        .disabled(selectedDealerID == nil)
        .opacity(selectedDealerID == nil ? 0.5 : 1)
        .buttonStyle(.plain)
    }

    // MARK: - 打牌中 UI（动画 + 提示 + 结束按钮）

    private var playingCenterUI: some View {
        VStack(spacing: 16) {
            // 动画区域：麻将牌与骰子
            ZStack {
                Image(systemName: "squareshape.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.tableGold.opacity(0.9))
                    .rotationEffect(.degrees(tileRotation))
                    .offset(x: -28, y: -12)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.tableRed.opacity(0.9))
                    .rotationEffect(.degrees(-tileRotation * 0.7))
                    .offset(x: 24, y: 8)

                Image(systemName: "dice.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.95))
                    .rotationEffect(.degrees(diceRotation))
                    .offset(x: stackOffset * 4, y: -20)
            }
            .frame(height: 60)
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    tileRotation = 360
                }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    diceRotation = 360
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    stackOffset = 6
                }
            }

            // 提示文字（跳动）
            Text("正在激烈交锋中...")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // 结束本局按钮
            Button {
                navigateToRound = true
            } label: {
                Text("结束本局，开始算分")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color.tableRed, Color.tableRed.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.tableRed.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(PlayingButtonStyle())
        }
        .padding(.vertical, 12)
    }

    private func startGame() {
        guard let dealerID = selectedDealerID else { return }
        let selectedIDs = Set(players.map(\.id))

        let descriptor = FetchDescriptor<GameSession>()
        guard let allSessions = try? modelContext.fetch(descriptor) else {
            createNewSession(dealerID: dealerID)
            return
        }

        let existingSession = allSessions.first { session in
            session.players.count == 4 && Set(session.players.map(\.id)) == selectedIDs
        }

        if let session = existingSession {
            session.currentDealerID = dealerID
            sessionCreated = session
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isPlaying = true
            }
        } else {
            createNewSession(dealerID: dealerID)
        }
    }

    private func createNewSession(dealerID: UUID) {
        let session = GameSession(currentDealerID: dealerID)
        modelContext.insert(session)
        session.players.append(contentsOf: players)
        sessionCreated = session
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isPlaying = true
        }
    }
}

// MARK: - 按压缩放按钮样式（春节 Q 弹）

private struct PlayingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 单侧座位（头像 + 名字 + 庄家角标）

private struct SeatView: View {
    let player: Player
    let isDealer: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PlayerAvatarView(player: player, size: 56, iconColor: Color.tableRed)
                        .background(Color.white, in: Circle())
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    if isDealer {
                        Text("庄")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.tableGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.tableGold.opacity(0.3), in: Capsule())
                            .overlay(Capsule().stroke(Color.tableRed, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                            .scaleEffect(isDealer ? 1.0 : 0.8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDealer)
                    }
                }
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GameTableView(players: [
            Player(name: "玩家一", avatarIcon: "person.circle.fill"),
            Player(name: "玩家二", avatarIcon: "person.circle.fill"),
            Player(name: "玩家三", avatarIcon: "person.circle.fill"),
            Player(name: "玩家四", avatarIcon: "person.circle.fill")
        ])
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
