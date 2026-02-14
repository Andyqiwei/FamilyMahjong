import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        // 使用 NavigationStack 包裹，为了后续能跳转到麻将桌页面
        NavigationStack {
            LobbyView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Player.self, inMemory: true)
}