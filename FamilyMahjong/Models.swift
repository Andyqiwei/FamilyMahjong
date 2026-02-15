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
    var totalScore: Int
    var winCount: Int
    var loseCount: Int
    var totalExposedKong: Int
    var totalConcealedKong: Int

    var gameSessions: [GameSession]

    init(
        id: UUID = UUID(),
        name: String,
        avatarIcon: String,
        avatarData: Data? = nil,
        totalScore: Int = 0,
        winCount: Int = 0,
        loseCount: Int = 0,
        totalExposedKong: Int = 0,
        totalConcealedKong: Int = 0
    ) {
        self.id = id
        self.name = name
        self.avatarIcon = avatarIcon
        self.avatarData = avatarData
        self.totalScore = totalScore
        self.winCount = winCount
        self.loseCount = loseCount
        self.totalExposedKong = totalExposedKong
        self.totalConcealedKong = totalConcealedKong
        self.gameSessions = []
    }
}

// MARK: - GameSession（当前牌局）

@Model
final class GameSession {
    var players: [Player]

    var currentDealerID: UUID

    var roundRecords: [RoundRecord]

    init(currentDealerID: UUID) {
        self.players = []
        self.currentDealerID = currentDealerID
        self.roundRecords = []
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
