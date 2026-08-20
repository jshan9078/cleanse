import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Model

struct Screenshot: Identifiable, Hashable {
    let url: URL
    let name: String
    let date: Date
    let size: Int64
    var id: URL { url }
}

@MainActor
final class Library: ObservableObject {
    @Published var shots: [Screenshot] = []
    @Published var selection: Set<URL> = []
    @Published var carouselIndex: Int = 0
    @Published var lastError: String?

    private var thumbCache: [URL: NSImage] = [:]

    static let scannedFolders: [URL] = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return ["Desktop", "Downloads", "Documents", "Pictures"].map {
            home.appendingPathComponent($0)
        }
    }()

    func scan() {
        let fm = FileManager.default
        var found: [Screenshot] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for folder in Self.scannedFolders {
            guard let items = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]) else { continue }
            for url in items {
                let name = url.lastPathComponent
                guard name.hasPrefix("Screenshot") else { continue }
                guard let type = UTType(filenameExtension: url.pathExtension),
                      type.conforms(to: .image) else { continue }
                let vals = try? url.resourceValues(forKeys: Set(keys))
                guard vals?.isRegularFile == true else { continue }
                found.append(Screenshot(
                    url: url,
                    name: name,
                    date: vals?.contentModificationDate ?? .distantPast,
                    size: Int64(vals?.fileSize ?? 0)))
            }
        }
        found.sort { $0.date > $1.date }
        shots = found
        selection = selection.filter { sel in found.contains { $0.url == sel } }
        if carouselIndex >= shots.count { carouselIndex = max(0, shots.count - 1) }
        let live = Set(found.map(\.url))
        thumbCache = thumbCache.filter { live.contains($0.key) }
    }

    func thumbnail(for url: URL, maxPixel: CGFloat = 480) -> NSImage? {
        if let cached = thumbCache[url] { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache[url] = img
        return img
    }

    /// Moves the given files to the Trash and removes them from the list.
    func trash(_ urls: [URL]) {
        let fm = FileManager.default
        var failures: [String] = []
        for url in urls {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                thumbCache[url] = nil
                selection.remove(url)
                if let idx = shots.firstIndex(where: { $0.url == url }) {
                    shots.remove(at: idx)
                    if idx < carouselIndex { carouselIndex -= 1 }
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if carouselIndex >= shots.count { carouselIndex = max(0, shots.count - 1) }
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}

// MARK: - Root view

enum ViewMode: String, CaseIterable {
    case grid = "Grid"
    case carousel = "Carousel"
}

struct ContentView: View {
    @StateObject private var library = Library()
    @State private var mode: ViewMode = .grid
    @State private var confirmBatchDelete = false

    var body: some View {
        Group {
            if library.shots.isEmpty {
                emptyState
            } else {
                switch mode {
                case .grid: GridScreen(library: library, confirmDelete: $confirmBatchDelete)
                case .carousel: CarouselScreen(library: library)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationSubtitle("\(library.shots.count) screenshots")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("View", selection: $mode) {
                    Label("Grid", systemImage: "square.grid.3x3").tag(ViewMode.grid)
                    Label("Carousel", systemImage: "rectangle.on.rectangle").tag(ViewMode.carousel)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    library.scan()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { library.scan() }
        .alert("Couldn't delete some files", isPresented: .init(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .confirmationDialog(
            "Move \(library.selection.count) screenshot\(library.selection.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirmBatchDelete, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                library.trash(Array(library.selection))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No screenshots found")
                .font(.title2)
            Text("Looked for files starting with “Screenshot” in Desktop, Downloads, Documents, and Pictures.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Scan Again") { library.scan() }
        }
        .padding(40)
    }
}

// MARK: - Grid

struct GridScreen: View {
    @ObservedObject var library: Library
    @Binding var confirmDelete: Bool

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.shots) { shot in
                        GridCell(shot: shot,
                                 selected: library.selection.contains(shot.url),
                                 thumb: library.thumbnail(for: shot.url))
                        .onTapGesture {
                            if library.selection.contains(shot.url) {
                                library.selection.remove(shot.url)
                            } else {
                                library.selection.insert(shot.url)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            HStack {
                Button("Select All") { library.selection = Set(library.shots.map(\.url)) }
                Button("Deselect All") { library.selection.removeAll() }
                    .disabled(library.selection.isEmpty)
                Spacer()
                Text(library.selection.isEmpty
                     ? "Click screenshots to select them"
                     : "\(library.selection.count) selected")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Selected", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(library.selection.isEmpty)
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct GridCell: View {
    let shot: Screenshot
    let selected: Bool
    let thumb: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .underPageBackgroundColor))
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.9),
                                     selected ? Color.accentColor : Color.black.opacity(0.25))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(shortName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shot.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: selected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    /// "Screenshot 2026-08-19 at 4.33.40 AM.png" → "Aug 19, 4.33.40 AM"
    private var shortName: String {
        shot.name
            .replacingOccurrences(of: "Screenshot ", with: "")
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: " at ", with: "  ")
    }
}

// MARK: - Carousel

struct CarouselScreen: View {
    @ObservedObject var library: Library
    @FocusState private var focused: Bool

    private var current: Screenshot? {
        guard library.shots.indices.contains(library.carouselIndex) else { return nil }
        return library.shots[library.carouselIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let shot = current {
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    if let img = NSImage(contentsOf: shot.url) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20)
                            .shadow(radius: 8)
                    } else {
                        Text("Couldn't load image").foregroundStyle(.secondary)
                    }
                    HStack {
                        arrowButton("chevron.left", disabled: library.carouselIndex == 0) {
                            library.carouselIndex -= 1
                        }
                        Spacer()
                        arrowButton("chevron.right",
                                    disabled: library.carouselIndex >= library.shots.count - 1) {
                            library.carouselIndex += 1
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shot.name).font(.headline).lineLimit(1).truncationMode(.middle)
                        Text("\(shot.date, format: .dateTime.year().month().day().hour().minute())  ·  \(ByteCountFormatter.string(fromByteCount: shot.size, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(library.carouselIndex + 1) of \(library.shots.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button(role: .destructive) {
                        library.trash([shot.url])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Moves this screenshot to the Trash")
                }
                .padding(12)
                .background(.bar)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            if library.carouselIndex > 0 { library.carouselIndex -= 1 }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if library.carouselIndex < library.shots.count - 1 { library.carouselIndex += 1 }
            return .handled
        }
        .onAppear { focused = true }
    }

    private func arrowButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

// MARK: - App

@main
struct CleanseApp: App {
    var body: some Scene {
        WindowGroup("Cleanse") {
            ContentView()
        }
    }
}
