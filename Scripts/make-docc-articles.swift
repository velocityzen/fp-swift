#!/usr/bin/env swift

// Makes the DocC articles in Sources/FP/FP.docc and Sources/FPRetry/FPRetry.docc from the
// sections of README.md, and the quick start on each landing page. README.md is the source:
// edit it, then run this script from the package root.
//
//     swift Scripts/make-docc-articles.swift            write the articles
//     swift Scripts/make-docc-articles.swift --check    fail when an article is out of date
//
// Both fail when a line of code in README.md is longer than 72 characters, because DocC
// cuts off longer lines in a normal browser window.

import Foundation

// MARK: - Settings

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let readmeURL = packageRoot.appending(path: "README.md")
let maxCodeLineLength = 72

let generatedNote =
    "<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->"
let quickStartStart =
    "<!-- Quick start: made from README.md by Scripts/make-docc-articles.swift. -->"
let quickStartEnd = "<!-- End of quick start. -->"

/// A DocC catalog, its landing page, and the README section whose first example and the
/// paragraph after it become the landing page's quick start.
struct Catalog {
    let path: String
    let landingPage: String
    let quickStartSection: String

    var url: URL { packageRoot.appending(path: path) }
}

let fp = Catalog(
    path: "Sources/FP/FP.docc",
    landingPage: "FP.md",
    quickStartSection: "Quick start"
)
let fpRetry = Catalog(
    path: "Sources/FPRetry/FPRetry.docc",
    landingPage: "FPRetry.md",
    quickStartSection: "Retrying"
)
let catalogs = [fp, fpRetry]

struct Article {
    let catalog: Catalog
    let file: String
    let title: String
    let abstract: String
    /// README sections, in order. A section with a heading level keeps its heading at that
    /// level. A section without one becomes the article's opening text, and its `###`
    /// headings move up to `##`.
    let sections: [(title: String, headingLevel: Int?)]
}

let articles = [
    Article(
        catalog: fp,
        file: "GettingStarted",
        title: "Getting Started",
        abstract: "Add fp-swift to your package, and write your first chain of results.",
        sections: [("Installation", 2), ("Quick start", 2)]
    ),
    Article(
        catalog: fp,
        file: "PipeOperators",
        title: "Pipe Operators",
        abstract: "Pass values through functions with `|>`, `|>>` and `|>>>`.",
        sections: [("Pipe operators", nil)]
    ),
    Article(
        catalog: fp,
        file: "WorkingWithResults",
        title: "Working with Results",
        abstract: "Run side effects, change and check results, and recover from failures.",
        sections: [("Working with results", nil), ("Recovering from failures", 2)]
    ),
    Article(
        catalog: fp,
        file: "Optionals",
        title: "Optionals",
        abstract: "Turn optionals into results, and work with optional values.",
        sections: [("Optionals", nil)]
    ),
    Article(
        catalog: fp,
        file: "DoNotation",
        title: "Do Notation",
        abstract: "Chain steps that need the values of the steps before them.",
        sections: [("Do notation", nil)]
    ),
    Article(
        catalog: fp,
        file: "AsyncResults",
        title: "Async Results",
        abstract: "Chain async steps, combine results, race calls, and add time limits.",
        sections: [
            ("Async results", nil), ("Combining results", 2), ("Racing and timeouts", 2),
        ]
    ),
    Article(
        catalog: fp,
        file: "Arrays",
        title: "Arrays",
        abstract: "Turn arrays into results, split arrays of results, and map with async code.",
        sections: [("Arrays", nil)]
    ),
    Article(
        catalog: fp,
        file: "AsyncSequences",
        title: "Async Sequences",
        abstract: "Work with async sequences of results, and map async sequences concurrently.",
        sections: [("Async sequences of results", nil), ("Concurrent mapping", 2)]
    ),
    Article(
        catalog: fp,
        file: "APIReference",
        title: "API Reference",
        abstract: "Every helper, and what it does.",
        sections: [("API reference", nil)]
    ),
    Article(
        catalog: fpRetry,
        file: "Retrying",
        title: "Retrying",
        abstract: "Retry async operations, and choose when and how long to wait.",
        sections: [("Retrying", nil)]
    ),
]

/// README sections that no article uses. DocC makes its own contents, the benchmarks are a
/// separate package, and the license is on the package page.
let readmeOnlySections: Set = ["Contents", "Benchmarks", "License"]

/// README links that DocC can't follow, and what replaces them in the articles. A link to a
/// README section becomes a `<doc:>` link, which shows the article or section title as its
/// text, so the sentence around it may change too.
let linkEdits: [(section: String, old: String, new: String)] = [
    ("Concurrent mapping", "(see [Arrays](#arrays))", "(see <doc:Arrays>)"),
    (
        "API reference",
        "The operators are in [Pipe operators](#pipe-operators), and the retry API is in [Retrying](#retrying).",
        "The operators are in <doc:PipeOperators>, and the retry API is in the `FPRetry` module."
    ),
]

// MARK: - Helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func read(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        fail("can't read \(url.path): \(error)")
    }
}

/// The lines of `text`, with `true` for each line inside a fenced code block, fences included.
func linesWithCodeFlag(_ text: String) -> [(line: String, isCode: Bool)] {
    var inFence = false
    return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        let isFence = line.hasPrefix("```")
        if isFence { inFence.toggle() }
        return (String(line), inFence || isFence)
    }
}

/// The text of each `## ` section of `markdown`, without its heading and outer blank lines.
func sections(of markdown: String) -> [String: String] {
    var result: [String: String] = [:]
    var title: String?
    var body: [String] = []

    func finish() {
        guard let title else { return }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .newlines)
        result[title] = text + "\n"
    }

    for (line, isCode) in linesWithCodeFlag(markdown) {
        if !isCode, line.hasPrefix("## ") {
            finish()
            title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            body = []
        } else {
            body.append(line)
        }
    }
    finish()
    return result
}

/// `text` with each `### ` heading outside code made a `## ` heading.
func promotingSubheadings(_ text: String) -> String {
    linesWithCodeFlag(text).map { line, isCode in
        !isCode && line.hasPrefix("### ") ? String(line.dropFirst()) : line
    }
    .joined(separator: "\n")
}

/// README code lines longer than `maxCodeLineLength`, as `README.md:<line>` descriptions.
func longCodeLines(in markdown: String) -> [String] {
    linesWithCodeFlag(markdown).enumerated().compactMap { index, entry in
        guard entry.isCode, entry.line.count > maxCodeLineLength else { return nil }
        return "README.md:\(index + 1) has \(entry.line.count) characters"
    }
}

/// Links in `text`, outside code, whose target is a README section or a relative path.
func linksDocCCantFollow(in text: String) -> [String] {
    let prose = linesWithCodeFlag(text).filter { !$0.isCode }.map(\.line).joined(separator: "\n")
    var links: [String] = []
    var rest = prose[...]
    while let open = rest.range(of: "](") {
        rest = rest[open.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { break }
        let target = String(rest[..<close])
        if !target.hasPrefix("http://"), !target.hasPrefix("https://") {
            links.append(target)
        }
        rest = rest[close...]
    }
    return links
}

/// The first code block of `section` and the paragraph after it.
func quickStart(from section: String, named name: String) -> String {
    let blocks = section.components(separatedBy: "\n\n")
    guard let codeStart = blocks.firstIndex(where: { $0.hasPrefix("```swift") }),
        let codeEnd = blocks[codeStart...].firstIndex(where: { $0.hasSuffix("```") }),
        codeEnd + 1 < blocks.count
    else {
        fail("the README's \"\(name)\" must have a code block with a paragraph after it")
    }
    let text = blocks[codeStart...codeEnd + 1].joined(separator: "\n\n")
    return text.trimmingCharacters(in: .newlines) + "\n"
}

// MARK: - Making the files

let readme = read(readmeURL)

let longLines = longCodeLines(in: readme)
if !longLines.isEmpty {
    fail(
        "code lines longer than \(maxCodeLineLength) characters, which DocC cuts off:\n"
            + longLines.joined(separator: "\n")
    )
}

var readmeSections = sections(of: readme)

let usedSections = Set(articles.flatMap { $0.sections.map(\.title) })
let unusedSections = readmeSections.keys.filter {
    !usedSections.contains($0) && !readmeOnlySections.contains($0)
}
if !unusedSections.isEmpty {
    fail(
        "no article uses the README sections \(unusedSections.sorted().joined(separator: ", ")). "
            + "Add them to an article in `articles`, or to `readmeOnlySections`."
    )
}

for edit in linkEdits {
    guard let text = readmeSections[edit.section] else {
        fail("the README has no \"\(edit.section)\" section")
    }
    guard text.components(separatedBy: edit.old).count == 2 else {
        fail("\"\(edit.section)\" must contain \(edit.old) exactly once")
    }
    readmeSections[edit.section] = text.replacingOccurrences(of: edit.old, with: edit.new)
}

/// The text of every file this script makes, by catalog path, then by file name.
var expected: [String: [String: String]] = [:]

for article in articles {
    var parts: [String] = []
    for (title, headingLevel) in article.sections {
        guard let text = readmeSections[title] else {
            fail("the README has no \"\(title)\" section, which \(article.file).md needs")
        }
        let links = linksDocCCantFollow(in: text)
        if !links.isEmpty {
            fail(
                "\"\(title)\" links to \(links.joined(separator: ", ")). Add a DocC link to linkEdits."
            )
        }
        if let headingLevel {
            parts.append("\(String(repeating: "#", count: headingLevel)) \(title)\n\n\(text)")
        } else {
            parts.append(promotingSubheadings(text))
        }
    }
    let body = parts.joined(separator: "\n")
    expected[article.catalog.path, default: [:]]["\(article.file).md"] =
        "# \(article.title)\n\n\(article.abstract)\n\n\(body)\n\(generatedNote)\n"
}

for catalog in catalogs {
    let landingURL = catalog.url.appending(path: catalog.landingPage)
    let landingPage = read(landingURL)
    guard let startRange = landingPage.range(of: quickStartStart),
        let endRange = landingPage.range(
            of: quickStartEnd,
            range: startRange.upperBound..<landingPage.endIndex
        )
    else {
        fail("\(catalog.landingPage) must contain \(quickStartStart) and \(quickStartEnd)")
    }
    guard let section = readmeSections[catalog.quickStartSection] else {
        fail("the README has no \"\(catalog.quickStartSection)\" section")
    }
    expected[catalog.path, default: [:]][catalog.landingPage] =
        landingPage[..<startRange.upperBound] + "\n\n"
        + quickStart(from: section, named: catalog.quickStartSection) + "\n"
        + landingPage[endRange.lowerBound...]

    for article in articles where article.catalog.path == catalog.path {
        if !landingPage.contains("<doc:\(article.file)>") {
            fail("\(catalog.landingPage) doesn't list <doc:\(article.file)> under Topics")
        }
    }
}

// MARK: - Writing or checking

let checkOnly = CommandLine.arguments.dropFirst().contains("--check")
var changed: [String] = []
var removed: [String] = []

for catalog in catalogs {
    let files = expected[catalog.path] ?? [:]
    for (file, text) in files.sorted(by: { $0.key < $1.key }) {
        let url = catalog.url.appending(path: file)
        let current = try? String(contentsOf: url, encoding: .utf8)
        guard current != text else { continue }
        changed.append(file)
        if !checkOnly {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                fail("can't write \(url.path): \(error)")
            }
        }
    }

    // Articles this script made earlier but no longer makes.
    let catalogFiles =
        (try? FileManager.default.contentsOfDirectory(atPath: catalog.url.path)) ?? []
    for file in catalogFiles.sorted() where file.hasSuffix(".md") && files[file] == nil {
        let url = catalog.url.appending(path: file)
        guard read(url).contains(generatedNote) else { continue }
        removed.append(file)
        if !checkOnly {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                fail("can't remove \(url.path): \(error)")
            }
        }
    }
}

if changed.isEmpty, removed.isEmpty {
    print("The DocC articles match README.md.")
} else if checkOnly {
    var problems: [String] = []
    if !changed.isEmpty {
        problems.append(
            "these DocC files don't match README.md: \(changed.joined(separator: ", "))."
        )
    }
    if !removed.isEmpty {
        problems.append(
            "these DocC files are no longer made from README.md: \(removed.joined(separator: ", "))."
        )
    }
    fail((problems + ["Run `swift Scripts/make-docc-articles.swift`."]).joined(separator: "\n"))
} else {
    if !changed.isEmpty { print("Updated \(changed.joined(separator: ", ")).") }
    if !removed.isEmpty { print("Removed \(removed.joined(separator: ", ")).") }
}
