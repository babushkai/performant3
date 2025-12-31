import SwiftUI
import AppKit

struct NewModelSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var framework: MLFramework = .coreML
    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var canImport: Bool {
        !name.isEmpty && selectedURL != nil && !isImporting
    }

    var importButtonHelpText: String {
        if isImporting {
            return "Importing model..."
        } else if selectedURL == nil {
            return "Select a model file first"
        } else if name.isEmpty {
            return "Enter a model name"
        } else {
            return "Import the model"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import Model")
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

            // Content - Scrollable
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step 1: Select File First
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("1.")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            Text("Select Model File")
                                .font(.headline)
                        }

                        if let url = selectedURL {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Change") { selectFile() }
                                    .buttonStyle(.bordered)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Button(action: selectFile) {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text("Choose Model File...")
                                            .fontWeight(.medium)
                                        Text(".mlmodel, .mlmodelc, .mlpackage")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // Step 2: Model Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("2.")
                                .font(.headline)
                                .foregroundColor(selectedURL != nil ? .accentColor : .secondary)
                            Text("Model Name")
                                .font(.headline)
                                .foregroundColor(selectedURL != nil ? .primary : .secondary)
                        }
                        TextField("Enter model name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(selectedURL == nil)
                    }

                    // Step 3: Framework
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("3.")
                                .font(.headline)
                                .foregroundColor(selectedURL != nil ? .accentColor : .secondary)
                            Text("Framework")
                                .font(.headline)
                                .foregroundColor(selectedURL != nil ? .primary : .secondary)
                        }
                        Picker("", selection: $framework) {
                            ForEach(MLFramework.allCases, id: \.self) { fw in
                                Text(fw.rawValue).tag(fw)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(selectedURL == nil)
                    }

                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: importModel) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Import Model", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport)
                .help(importButtonHelpText)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "mlmodel")!,
            .init(filenameExtension: "mlmodelc")!,
            .init(filenameExtension: "mlpackage")!
        ]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func importModel() {
        guard let url = selectedURL else { return }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                try await appState.importModel(from: url, name: name, framework: framework)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
