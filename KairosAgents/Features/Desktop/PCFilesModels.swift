import SwiftUI

nonisolated enum PCKind: Hashable, Sendable { case folder, text, image, other }

nonisolated struct PCItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var kind: PCKind
    var bytes: Int = 0
    var modified: String
    /// Sort key for the date: bigger is newer.
    var age: Int

    var symbol: String {
        switch kind {
        case .folder: "folder"
        case .text: name.hasSuffix(".md") || name.hasSuffix(".txt") ? "doc.text" : "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .other: "doc"
        }
    }

    var size: String {
        guard kind != .folder else { return "" }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        return "\(max(1, bytes / 1000)) KB"
    }
}

nonisolated enum PCSort: String, CaseIterable, Hashable, Sendable {
    case name = "Name", date = "Date", size = "Size"
}

/// What the PC files screens read. The real one lists folders over the desktop's file routes.
protocol PCFilesProviding {
    func items(in path: String) -> [PCItem]
    func text(of path: String) -> String
    func displayPath(_ path: String) -> String
}

struct PCFilesSample: PCFilesProviding {
    static let places: [PCItem] = [
        PCItem(name: "Projects", path: "Projects", kind: .folder, modified: "Today", age: 100),
        PCItem(name: "Documents", path: "Documents", kind: .folder, modified: "Today", age: 99),
        PCItem(name: "Downloads", path: "Downloads", kind: .folder, modified: "Yesterday", age: 90),
        PCItem(name: "Desktop", path: "Desktop", kind: .folder, modified: "Mon", age: 80),
    ]

    static let placeSymbols: [String: String] = [
        "Projects": "hammer", "Documents": "doc.on.doc", "Downloads": "arrow.down.circle", "Desktop": "menubar.dock.rectangle",
    ]

    private static let tree: [String: [PCItem]] = [
        "Projects": [
            PCItem(name: "shop-site", path: "Projects/shop-site", kind: .folder, modified: "Today", age: 100),
            PCItem(name: "inventory-api", path: "Projects/inventory-api", kind: .folder, modified: "Yesterday", age: 90),
            PCItem(name: "recipe-notes", path: "Projects/recipe-notes", kind: .folder, modified: "Mon", age: 70),
        ],
        "Projects/shop-site": [
            PCItem(name: "src", path: "Projects/shop-site/src", kind: .folder, modified: "Today", age: 100),
            PCItem(name: "public", path: "Projects/shop-site/public", kind: .folder, modified: "Mon", age: 70),
            PCItem(name: "README.md", path: "Projects/shop-site/README.md", kind: .text, bytes: 1_800, modified: "Oct 2", age: 40),
            PCItem(name: "package.json", path: "Projects/shop-site/package.json", kind: .text, bytes: 900, modified: "Today", age: 98),
        ],
        "Projects/shop-site/src": [
            PCItem(name: "main.tsx", path: "Projects/shop-site/src/main.tsx", kind: .text, bytes: 600, modified: "Sep 14", age: 30),
            PCItem(name: "layout.css", path: "Projects/shop-site/src/layout.css", kind: .text, bytes: 4_100, modified: "Today", age: 99),
        ],
        "Projects/shop-site/public": [
            PCItem(name: "hero.jpg", path: "Projects/shop-site/public/hero.jpg", kind: .image, bytes: 482_000, modified: "Mon", age: 70),
            PCItem(name: "favicon.svg", path: "Projects/shop-site/public/favicon.svg", kind: .image, bytes: 1_200, modified: "Aug 30", age: 20),
        ],
        "Projects/inventory-api": [
            PCItem(name: "app", path: "Projects/inventory-api/app", kind: .folder, modified: "Yesterday", age: 90),
            PCItem(name: "requirements.txt", path: "Projects/inventory-api/requirements.txt", kind: .text, bytes: 300, modified: "Oct 20", age: 50),
        ],
        "Projects/inventory-api/app": [
            PCItem(name: "alerts.py", path: "Projects/inventory-api/app/alerts.py", kind: .text, bytes: 400, modified: "Yesterday", age: 90),
            PCItem(name: "models.py", path: "Projects/inventory-api/app/models.py", kind: .text, bytes: 2_600, modified: "Oct 20", age: 50),
        ],
        "Projects/recipe-notes": [
            PCItem(name: "soups.md", path: "Projects/recipe-notes/soups.md", kind: .text, bytes: 3_200, modified: "Mon", age: 70),
        ],
        "Documents": [
            PCItem(name: "Shop", path: "Documents/Shop", kind: .folder, modified: "Today", age: 99),
            PCItem(name: "Shop opening plan.md", path: "Documents/Shop opening plan.md", kind: .text, bytes: 2_400, modified: "Today", age: 98),
            PCItem(name: "Report draft.txt", path: "Documents/Report draft.txt", kind: .text, bytes: 5_100, modified: "Yesterday", age: 90),
            PCItem(name: "Budget 2026.xlsx", path: "Documents/Budget 2026.xlsx", kind: .other, bytes: 38_000, modified: "Oct 28", age: 60),
        ],
        "Documents/Shop": [
            PCItem(name: "Price list.txt", path: "Documents/Shop/Price list.txt", kind: .text, bytes: 1_100, modified: "Today", age: 99),
            PCItem(name: "Storefront.jpg", path: "Documents/Shop/Storefront.jpg", kind: .image, bytes: 1_920_000, modified: "Oct 12", age: 45),
        ],
        "Downloads": [
            PCItem(name: "bike-manual.pdf", path: "Downloads/bike-manual.pdf", kind: .other, bytes: 2_300_000, modified: "Yesterday", age: 90),
            PCItem(name: "logo-sketch.png", path: "Downloads/logo-sketch.png", kind: .image, bytes: 210_000, modified: "Mon", age: 70),
            PCItem(name: "notes.txt", path: "Downloads/notes.txt", kind: .text, bytes: 700, modified: "Sep 3", age: 25),
        ],
        "Desktop": [
            PCItem(name: "To do.txt", path: "Desktop/To do.txt", kind: .text, bytes: 400, modified: "Today", age: 100),
        ],
    ]

    func items(in path: String) -> [PCItem] {
        path.isEmpty ? Self.places : (Self.tree[path] ?? [])
    }

    func count(in path: String) -> Int { Self.tree[path]?.count ?? 0 }

    func displayPath(_ path: String) -> String {
        if path.hasPrefix("Projects") { return "C:/" + path }
        return path.isEmpty ? "This PC" : "C:/Users/you/" + path
    }

    func text(of path: String) -> String {
        if path.hasSuffix("Shop opening plan.md") {
            return """
            # Shop opening plan

            - Friday: window display and price tags
            - Saturday 9:00: doors open, coffee for the first 20
            - Sunday: count stock, order more bells and locks
            """
        }
        if path.hasSuffix(".py") {
            return """
            def low_stock(items, limit=5):
                \"\"\"Items at or under the limit.\"\"\"
                return [i for i in items if i.count <= limit]
            """
        }
        if path.hasSuffix(".json") {
            return """
            {
              "name": "shop-site",
              "private": true,
              "scripts": { "dev": "vite", "build": "vite build" }
            }
            """
        }
        if path.hasSuffix(".css") {
            return """
            .page {
              display: flex;
              flex-direction: column;
              gap: 16px;
            }
            """
        }
        if path.hasSuffix("Price list.txt") {
            return "Blue bell        12.00\nBike lock        24.00\nRear light       18.50\nSaddle bag       32.00"
        }
        return "Call the supplier about the red city bikes.\nPick up the window paint.\nWrite the Friday report."
    }
}
