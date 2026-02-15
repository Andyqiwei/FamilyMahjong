//
//  Models.swift
//  FamilyMahjong
//
//  SwiftData models for Mahjong scoring app.
//

import Foundation
import SwiftData

// MARK: - 杠牌明细（本局每人的明杠/暗杠数）

struct KongDetail: Codable {
    var playerID: UUID
    var exposedKongCount: Int   // 明杠数
    var concealedKongCount: Int // 暗杠数
}

// MARK: - Player（玩家）

@Model
final class Player {
    var id: UUID
    var name: String
    var avatarIcon: String
    var avatarData: Data?
    var gameSessions: [GameSession]

    init(
        id: UUID = UUID(),
        name: String,
        avatarIcon: String,
        avatarData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarIcon = avatarIcon
        self.avatarData = avatarData
        self.gameSessions = []
    }
}

// MARK: - GameSession（当前牌局）

@Model
final class GameSession {
    @Relationship(inverse: \Player.gameSessions) var players: [Player]

    var currentDealerID: UUID

    var roundRecords: [RoundRecord]

    var createdAt: Date

    init(currentDealerID: UUID) {
        self.players = []
        self.currentDealerID = currentDealerID
        self.roundRecords = []
        self.createdAt = Date()
    }
}

// MARK: - RoundRecord（单局历史记录）

@Model
final class RoundRecord {
    var id: UUID
    var timestamp: Date
    var roundNumber: Int
    var winnerID: UUID
    var loserID: UUID?
    var isSelfDrawn: Bool
    var kongDetails: [KongDetail]
    var dealerID: UUID

    var gameSession: GameSession?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        roundNumber: Int,
        winnerID: UUID,
        loserID: UUID? = nil,
        isSelfDrawn: Bool,
        kongDetails: [KongDetail] = [],
        gameSession: GameSession? = nil,
        dealerID: UUID
    ) {
        self.id = id
        self.timestamp = timestamp
        self.roundNumber = roundNumber
        self.winnerID = winnerID
        self.loserID = loserID
        self.isSelfDrawn = isSelfDrawn
        self.kongDetails = kongDetails
        self.gameSession = gameSession
        self.dealerID = dealerID
    }
}
