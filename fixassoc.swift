// fixassoc — view and change default apps for the file types found in a folder.
//
// Usage:  fixassoc [-r] [folder]      (folder defaults to the current directory)
//   -r    scan subfolders too (skips hidden files and app/package bundles)
//
// Build:  swiftc -O fixassoc.swift -o fixassoc
//
// Do NOT run with sudo: default-app settings are per user, so sudo would
// change root's preferences instead of yours.

import AppKit
import UniformTypeIdentifiers

// MARK: - Terminal helpers

let isTTY = isatty(STDOUT_FILENO) != 0
func style(_ s: String, _ code: String) -> String { isTTY ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
func bold(_ s: String) -> String { style(s, "1") }
func dim(_ s: String) -> String { style(s, "2") }
func green(_ s: String) -> String { style(s, "32") }
func yellow(_ s: String) -> String { style(s, "33") }
func red(_ s: String) -> String { style(s, "31") }

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n - 1)) + "…" : s + String(repeating: " ", count: n - s.count)
}

func prompt(_ msg: String) -> String? {
    print(msg, terminator: "")
    fflush(stdout)
    return readLine()?.trimmingCharacters(in: .whitespaces)
}

// MARK: - Arguments

if getuid() == 0 {
    print(red("Don't run this with sudo — it would change root's defaults, not yours."))
    exit(1)
}

var recursive = false
var folder = FileManager.default.currentDirectoryPath
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "-r", "--recursive": recursive = true
    case "-h", "--help":
        print("Usage: fixassoc [-r] [folder]")
        exit(0)
    default: folder = (arg as NSString).expandingTildeInPath
    }
}

// MARK: - Scan folder

func scanExtensions(in dir: String, recursive: Bool) -> [(ext: String, count: Int)] {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: dir)
    var counts: [String: Int] = [:]
    let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey]

    func record(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return }
        counts[ext, default: 0] += 1
    }

    if recursive {
        let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = e?.nextObject() as? URL {
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true || v?.isPackage == true { record(url) }
        }
    } else {
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles])) ?? []
        for url in items {
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true || v?.isPackage == true { record(url) }
        }
    }
    return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.ext < $1.ext }
}

// MARK: - Apps

func appName(_ url: URL?) -> String {
    guard let url else { return "—" }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

func allInstalledApps() -> [URL] {
    let fm = FileManager.default
    let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                 "/Applications/Utilities", NSHomeDirectory() + "/Applications",
                 "/System/Library/CoreServices/Applications"]
    var seen = Set<String>(), apps: [URL] = []
    for root in roots {
        guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
        while let url = e.nextObject() as? URL {
            if e.level > 2 { e.skipDescendants(); continue }
            if url.pathExtension == "app", seen.insert(url.resolvingSymlinksInPath().path).inserted {
                apps.append(url)
            }
        }
    }
    return apps.sorted { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }
}

func setDefault(app: URL, for type: UTType) -> Error? {
    var result: Error?
    var done = false
    NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { err in
        result = err
        done = true
    }
    while !done { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return result
}

// MARK: - UI

struct Row { let ext: String; let count: Int; let type: UTType }

func loadRows() -> [Row] {
    scanExtensions(in: folder, recursive: recursive).map { item in
        Row(ext: item.ext, count: item.count,
            type: UTType(filenameExtension: item.ext) ?? .data)
    }
}

func printTable(_ rows: [Row]) {
    print()
    print(bold("File types in \(folder)\(recursive ? " (recursive)" : "")"))
    print(dim(pad("  #", 6) + pad("ext", 12) + pad("count", 8) + pad("default app", 28) + "type"))
    for (i, r) in rows.enumerated() {
        let app = NSWorkspace.shared.urlForApplication(toOpen: r.type)
        let appStr = app == nil ? red(pad("(none)", 28)) : pad(appName(app), 28)
        let uti = r.type.isDynamic ? yellow("(unregistered type)") : dim(r.type.identifier)
        print(pad(String(format: "%4d", i + 1), 6) + pad("." + r.ext, 12) + pad(String(r.count), 8) + appStr + uti)
    }
}

/// Let the user pick an app. Returns nil if cancelled.
func chooseApp(for row: Row) -> URL? {
    let current = NSWorkspace.shared.urlForApplication(toOpen: row.type)
    let capable = NSWorkspace.shared.urlsForApplications(toOpen: row.type)
    var showingAll = capable.isEmpty
    var filter = ""
    var all: [URL]? = nil

    while true {
        var list = showingAll ? (all ?? { all = allInstalledApps(); return all! }()) : capable
        if !filter.isEmpty { list = list.filter { appName($0).localizedCaseInsensitiveContains(filter) } }

        print()
        let header = showingAll ? "All installed apps" : "Apps that say they can open .\(row.ext)"
        print(bold(header) + (filter.isEmpty ? "" : dim("  filter: \"\(filter)\"")))
        if list.isEmpty { print(dim("  (no matches)")) }
        for (i, url) in list.enumerated() {
            let mark = url.standardizedFileURL == current?.standardizedFileURL ? green(" ← current") : ""
            print(String(format: "%4d  ", i + 1) + appName(url) + dim("  " + url.deletingLastPathComponent().path) + mark)
        }
        print(dim("\nnumber = choose · text = filter · a = toggle all apps · Enter/b = back"))
        guard let input = prompt("> "), !input.isEmpty, input != "b" else { return nil }

        if input == "a" { showingAll.toggle(); filter = ""; continue }
        if let n = Int(input), n >= 1, n <= list.count { return list[n - 1] }
        filter = input
    }
}

func siblingExtensions(of type: UTType, excluding ext: String) -> [String] {
    (type.tags[.filenameExtension] ?? []).filter { $0.lowercased() != ext }
}

// MARK: - Main loop

var rows = loadRows()
if rows.isEmpty {
    print("No files with extensions found in \(folder).")
    exit(0)
}

while true {
    printTable(rows)
    print(dim("\nnumber (or .ext) = change default · r = rescan · q = quit"))
    guard let input = prompt("> ")?.lowercased() else { break }
    if input == "q" { break }
    if input == "r" || input.isEmpty { rows = loadRows(); continue }

    let row: Row?
    if let n = Int(input), n >= 1, n <= rows.count {
        row = rows[n - 1]
    } else {
        let ext = input.hasPrefix(".") ? String(input.dropFirst()) : input
        row = rows.first { $0.ext == ext }
            ?? UTType(filenameExtension: ext).map { Row(ext: ext, count: 0, type: $0) }
    }
    guard let row else { print(red("Not found.")); continue }

    print()
    print(bold(".\(row.ext)") + dim("  \(row.type.identifier)")
          + (row.type.localizedDescription.map { dim("  (\($0))") } ?? ""))
    if row.type.isDynamic {
        print(yellow("No installed app declares this extension, so macOS gave it a temporary type ID."))
        print(yellow("Setting a default may not stick; installing an app that declares it usually fixes that."))
    }

    guard let app = chooseApp(for: row) else { continue }
    if let err = setDefault(app: app, for: row.type) {
        print(red("Failed: \(err.localizedDescription)"))
        continue
    }
    let now = NSWorkspace.shared.urlForApplication(toOpen: row.type)
    if now?.standardizedFileURL == app.standardizedFileURL {
        print(green("✓ .\(row.ext) now opens with \(appName(app))"))
    } else {
        print(yellow("macOS accepted the change but still reports \(appName(now)). It may need a moment, or the app may not support this type."))
    }
    let siblings = siblingExtensions(of: row.type, excluding: row.ext)
    if !siblings.isEmpty {
        print(dim("  (also applies to: " + siblings.map { "." + $0 }.joined(separator: ", ") + " — same file type)"))
    }
}
