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

                    // 开始本局按钮（桌心）
                    startButton
                        .position(x: centerX, y: centerY)
                }
                .frame(width: width, height: height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func startGame() {
        guard let dealerID = selectedDealerID else { return }
        let session = GameSession(currentDealerID: dealerID)
        modelContext.insert(session)
        session.players.append(contentsOf: players)
        sessionCreated = session
        navigateToRound = true
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
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.tableGold.opacity(0.5), Color.tableGold.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: player.avatarIcon)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.tableRed)
                        )
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
