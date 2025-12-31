import SwiftUI
import AppKit

struct DatasetsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedType: DatasetType?
    @State private var showingDeleteConfirmation = false
    @State private var datasetToDelete: Dataset?
    @State private var isDraggingOver = false

    var filteredDatasets: [Dataset] {
        var datasets = appState.datasets

        if !searchText.isEmpty {
            datasets = datasets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if let type = selectedType {
            datasets = datasets.filter { $0.type == type }
        }

        return datasets
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                // Check if it's a directory
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    DispatchQueue.main.async {
                        appState.errorMessage = "Please drop a folder containing dataset files"
                    }
                    return
                }

                // Import the dataset
                DispatchQueue.main.async {
                    Task {
                        do {
                            try await appState.importDataset(
                                from: url,
                                name: url.lastPathComponent,
                                type: .images // Default to images, could be improved
                            )
                        } catch {
                            appState.errorMessage = "Failed to import dataset: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Datasets")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("\(appState.datasets.count) datasets")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { appState.showImportDatasetSheet = true }) {
                    Label("Import Dataset", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            // Filters
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search datasets...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Picker("Type", selection: $selectedType) {
                    Text("All Types").tag(nil as DatasetType?)
                    ForEach(DatasetType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as DatasetType?)
                    }
                }
                .frame(width: 140)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            // Datasets Grid
            if filteredDatasets.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No Datasets",
                    message: searchText.isEmpty ? "Import a dataset to get started" : "No datasets match your search",
                    actionTitle: searchText.isEmpty ? "Import Dataset" : nil,
                    action: searchText.isEmpty ? { appState.showImportDatasetSheet = true } : nil
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 400))
                    ], spacing: 16) {
                        ForEach(filteredDatasets) { dataset in
                            DatasetCard(
                                dataset: dataset,
                                onDelete: {
                                    datasetToDelete = dataset
                                    showingDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay {
            if isDraggingOver {
                DatasetDropZone()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .alert("Delete Dataset", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let dataset = datasetToDelete {
                    Task { await appState.deleteDataset(dataset) }
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(datasetToDelete?.name ?? "")'? This will remove the dataset files.")
        }
    }
}

// MARK: - Dataset Card

struct DatasetCard: View {
    let dataset: Dataset
    let onDelete: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(dataset.type.color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: dataset.type.icon)
                        .foregroundColor(dataset.type.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(dataset.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(dataset.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button(action: { openInFinder() }) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Stats
            HStack(spacing: 16) {
                DatasetStat(icon: "doc.on.doc", value: "\(dataset.sampleCount)", label: "Samples")
                DatasetStat(icon: "internaldrive", value: formatBytes(dataset.size), label: "Size")
            }

            // Classes (if available)
            if !dataset.classes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Classes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(dataset.classes.prefix(10), id: \.self) { className in
                                Text(className)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            if dataset.classes.count > 10 {
                                Text("+\(dataset.classes.count - 10) more")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Footer
            HStack {
                Text("Imported \(dataset.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func openInFinder() {
        if let path = dataset.path {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }
}

// MARK: - Dataset Stat

struct DatasetStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Dataset Drop Zone

struct DatasetDropZone: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.white)

                Text("Drop Folder to Import Dataset")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Drop a folder containing images organized by class")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.9))
            )
        }
    }
}

