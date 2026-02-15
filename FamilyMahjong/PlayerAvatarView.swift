//
//  PlayerAvatarView.swift
//  FamilyMahjong
//
//  共享头像视图：有 avatarData 显示照片圆，无则显示默认图标圆。
//

import SwiftUI
import UIKit

/// 根据 Player 显示头像：有 avatarData 为照片圆，否则为默认图标圆。
struct PlayerAvatarView: View {
    let player: Player
    let size: CGFloat
    var iconColor: Color = Color(red: 230/255, green: 57/255, blue: 70/255)

    var body: some View {
        Group {
            if let data = player.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 233/255, green: 196/255, blue: 106/255).opacity(0.4),
                                Color(red: 244/255, green: 162/255, blue: 97/255).opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: player.avatarIcon)
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(iconColor)
                    )
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        PlayerAvatarView(player: Player(name: "测试", avatarIcon: "person.circle.fill"), size: 64)
        PlayerAvatarView(player: Player(name: "测试", avatarIcon: "person.circle.fill"), size: 40, iconColor: .red)
    }
    .padding()
}
