//
//  DataManagementView.swift
//  FamilyMahjong
//
//  数据管理设置：导出/导入 CSV、一键清空所有战绩。
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// 用于 ShareLink 的 CSV 导出项。使用 FileRepresentation 写入临时文件，避免分享时内容为空。
private struct CSVExportItem: Transferable {
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let fileName = "战绩日志_\(Int(Date().timeIntervalSince1970)).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try item.content.write(to: tempURL, atomically: true, encoding: .utf8)
            return SentTransferredFile(tempURL)
        }
    }
}

// MARK: - 主题色（春节卡通风）

private extension Color {
    static let mgmtRed = Color(red: 230/255, green: 57/255, blue: 70/255)
    static let mgmtGold = Color(red: 233/255, green: 196/255, blue: 106/255)
    static let mgmtBackground = Color(red: 248/255, green: 249/255, blue: 250/255)
}

// MARK: - DataManagementView

struct DataManagementView: View {
    @Query(sort: \RoundRecord.timestamp, order: .reverse) private var records: [RoundRecord]
    @Query(sort: \Player.name) private var players: [Player]
    @Environment(\.modelContext) private var modelContext

    private var scoringViewModel = ScoringViewModel()

    @State private var showFileImporter = false
    @State private var importFileURL: URL?
    @State private var showImportModeDialog = false
    @State private var importResultMessage: String?
    @State private var showImportResultAlert = false
    @State private var showClearFirstAlert = false
    @State private var showClearSecondAlert = false

    private var csvExportString: String {
        scoringViewModel.exportCSV(records: records, players: players)
    }

    var body: some View {
        ZStack {
            Color.mgmtBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    exportSection
                    importSection
                    clearAllSection
                }
                .padding(20)
            }
        }
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importFileURL = url
                showImportModeDialog = true
            case .failure:
                importResultMessage = "无法选择文件"
                showImportResultAlert = true
            }
        }
        .confirmationDialog("导入方式", isPresented: $showImportModeDialog) {
            Button("追加到现有日志") {
                if let url = importFileURL {
                    performImport(url: url, mode: .append)
                }
                importFileURL = nil
                showImportModeDialog = false
            }
            Button("清空并覆盖原有日志", role: .destructive) {
                if let url = importFileURL {
                    performImport(url: url, mode: .overwrite)
                }
                importFileURL = nil
                showImportModeDialog = false
            }
            Button("取消", role: .cancel) {
                importFileURL = nil
                showImportModeDialog = false
            }
        } message: {
            Text("请选择如何导入 CSV 数据")
        }
        .alert("导入结果", isPresented: $showImportResultAlert) {
            Button("确定", role: .cancel) {
                importResultMessage = nil
            }
        } message: {
            if let msg = importResultMessage {
                Text(msg)
            }
        }
        .alert("确认清空", isPresented: $showClearFirstAlert) {
            Button("取消", role: .cancel) {}
            Button("继续") {
                showClearFirstAlert = false
                showClearSecondAlert = true
            }
        } message: {
            Text("确定要清空所有对局日志吗？此操作将导致所有人积分归零！")
        }
        .alert("最终警告", isPresented: $showClearSecondAlert) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                clearAllRecords()
            }
        } message: {
            Text("删除后无法恢复！你真的确定吗？")
        }
    }

    // MARK: - 导出 CSV

    private var exportSection: some View {
        card(title: "导出 CSV") {
            ShareLink(
                item: CSVExportItem(content: csvExportString),
                preview: SharePreview("战绩日志.csv", image: Image(systemName: "doc.text"))
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                    Text("导出战绩到 CSV")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.mgmtRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 导入 CSV

    private var importSection: some View {
        card(title: "导入 CSV") {
            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                    Text("选择 CSV 文件导入")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.mgmtRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // MARK: - 一键清空

    private var clearAllSection: some View {
        card(title: "⚠️ 危险操作") {
            Button {
                showClearFirstAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                    Text("一键清空所有战绩")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.mgmtRed)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.mgmtRed)
            content()
        }
    }

    private func performImport(url: URL, mode: ScoringViewModel.ImportMode) {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let string = try String(contentsOf: url, encoding: .utf8)
            let result = scoringViewModel.importCSV(csvString: string, context: modelContext, currentPlayers: players, mode: mode)
            switch result {
            case .success:
                try? modelContext.save()
                importResultMessage = "导入成功"
            case .formatError(let reason):
                importResultMessage = "格式不对：\(reason)。请重新选择文件导入。"
            }
        } catch {
            importResultMessage = "导入失败：\(error.localizedDescription)"
        }
        showImportResultAlert = true
    }

    private func clearAllRecords() {
        let descriptor = FetchDescriptor<RoundRecord>()
        guard let allRecords = try? modelContext.fetch(descriptor) else { return }
        for record in allRecords {
            modelContext.delete(record)
        }
        try? modelContext.save()
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
    NavigationStack {
        DataManagementView()
    }
    .modelContainer(for: [Player.self, GameSession.self, RoundRecord.self], inMemory: true)
}
