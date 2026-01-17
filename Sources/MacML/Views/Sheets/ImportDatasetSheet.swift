import SwiftUI
import AppKit

struct ImportDatasetSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: DatasetType = .images
    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var canImport: Bool {
        !name.isEmpty && selectedURL != nil && !isImporting
    }

    var importButtonHelpText: String {
        if isImporting {
            return "Importing dataset..."
        } else if name.isEmpty && selectedURL == nil {
            return "Enter a name and select a folder to import"
        } else if name.isEmpty {
            return "Enter a dataset name"
        } else if selectedURL == nil {
            return "Select a source folder"
        } else {
            return "Import the dataset"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L.importDatasetTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Dataset Name
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.datasetName)
                        .font(.headline)
                    TextField(L.datasetName, text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Type Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.datasetType)
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(DatasetType.allCases, id: \.self) { datasetType in
                            DatasetTypeButton(
                                type: datasetType,
                                isSelected: type == datasetType
                            ) {
                                type = datasetType
                            }
                        }
                    }
                }

                // Folder Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.sourceFolder)
                        .font(.headline)

                    HStack {
                        if let url = selectedURL {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(L.change) { selectFolder() }
                                .buttonStyle(.borderless)
                        } else {
                            Button(action: selectFolder) {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                    Text(L.selectFolder)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    Text(typeHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button(L.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: importDataset) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(L.importBtn)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport)
                .help(importButtonHelpText)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
    }

    private var typeHint: String {
        switch type {
        case .images:
            return "Select a folder containing images organized by class (subfolder per class)"
        case .text:
            return "Select a folder containing text files (.txt, .csv, .json)"
        case .tabular:
            return "Select a folder containing CSV or Excel files"
        case .audio:
            return "Select a folder containing audio files (.wav, .mp3, .m4a)"
        case .video:
            return "Select a folder containing video files (.mp4, .mov)"
        case .custom:
            return "Select a folder containing your custom dataset format"
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func importDataset() {
        guard let url = selectedURL else { return }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                try await appState.importDataset(from: url, name: name, type: type)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

// MARK: - Dataset Type Button

struct DatasetTypeButton: View {
    let type: DatasetType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : type.color)
                Text(type.rawValue)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? type.color : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? type.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
