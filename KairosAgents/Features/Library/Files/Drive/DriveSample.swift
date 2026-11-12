import Foundation

/// Made-up Drive content for a small bike shop.
nonisolated enum DriveSample {
    static let shopAccount = "acct-shop"
    static let booksAccount = "acct-books"
    static let ownerEmail = "shop@example.com"

    // Ids the debug states open straight into.
    static let shopFolder = "f-shop"
    static let reportsFolder = "f-reports"
    static let inventory = "s-inventory"
    static let survey = "o-survey"
    static let report = "d-report"
    static let opening = "d-hours"
    static let rota = "s-rota"

    static let accounts: [DriveAccount] = [
        DriveAccount(id: shopAccount, email: ownerEmail, usedGB: 6.2, totalGB: 15, broken: false, canSend: true),
        DriveAccount(id: booksAccount, email: "books@example.com", usedGB: 2.1, totalGB: 15, broken: true, canSend: false),
    ]

    private static func hoursAgo(_ hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }

    private static let owner = DriveMember(audience: .person, address: ownerEmail, access: .owner)
    private static let mechanic = DriveMember(audience: .person, address: "mechanic@example.com", access: .editor)
    private static let team = DriveMember(audience: .group, address: "team@example.com", access: .commenter)
    private static let anyone = DriveMember(audience: .anyone, address: "", access: .viewer)
    private static let supplier = DriveMember(audience: .person, address: "orders@example.com", access: .owner)

    private static func revisions(_ hours: [Double]) -> [Date] { hours.map { hoursAgo($0) } }

    private static func folder(_ id: String, _ name: String, parent: String? = nil, hours: Double, starred: Bool = false, shared: Bool = false) -> DriveFile {
        DriveFile(
            id: id, account: shopAccount, name: name, kind: .folder, modified: hoursAgo(hours),
            starred: starred, parent: parent, sharedWithMe: shared,
            members: shared ? [supplier, owner.with(.viewer)] : [owner]
        )
    }

    private static func item(
        _ id: String, _ name: String, _ kind: DriveKind, parent: String? = nil, size: Int64 = 0, hours: Double,
        starred: Bool = false, trashed: Bool = false, shared: Bool = false, members: [DriveMember]? = nil, body: String = ""
    ) -> DriveFile {
        DriveFile(
            id: id, account: shopAccount, name: name, kind: kind, size: size, modified: hoursAgo(hours),
            starred: starred, trashed: trashed, parent: parent, sharedWithMe: shared,
            members: members ?? (shared ? [supplier, owner.with(.commenter)] : [owner]),
            revisions: revisions([hours, hours + 26, hours + 75]),
            body: body
        )
    }

    static var files: [DriveFile] {
        var list: [DriveFile] = [
            folder(shopFolder, "Bike shop", hours: 5, starred: true),
            folder("f-photos", "Photos", parent: shopFolder, hours: 30),
            folder(reportsFolder, "Reports", hours: 20),
            folder("f-receipts", "Receipts", hours: 140),
            folder("f-supplier", "Supplier price lists", hours: 60, shared: true),

            item(report, "Monthly report", .doc, parent: reportsFolder, hours: 2, starred: true, members: [owner, mechanic, team],
                 body: "Monthly report\n\nThe report is due Friday. Sales were up on last month, mostly from the spring tune-up offer. Repairs took a little longer than usual because two parts orders arrived late.\n\nNext steps: reorder brake pads early, and try a weekend service slot."),
            item("s-sales", "Sales by month", .sheet, parent: reportsFolder, hours: 9),
            item("p-q3", "Q3 summary.pdf", .pdf, parent: reportsFolder, size: 1_480_000, hours: 220,
                 body: "Q3 summary\n\nBikes sold: 42\nRepairs: 118\nBusiest week: the first week of the school holidays."),
            item("s-repairs", "Repair log", .sheet, parent: reportsFolder, hours: 26),

            item("d-menu", "Spring service menu", .doc, parent: shopFolder, hours: 48,
                 body: "Spring service menu\n\nBasic tune-up: gears, brakes, tyre check.\nFull service: everything in the tune-up, plus a wheel true and a chain clean.\nAsk at the counter about same-day repairs."),
            item(inventory, "Inventory", .sheet, parent: shopFolder, hours: 3, starred: true, members: [owner, mechanic]),
            item(survey, "Customer survey", .form, parent: shopFolder, hours: 12, members: [owner, team]),
            item("l-window", "Store window ideas", .slides, parent: shopFolder, hours: 96,
                 body: "Store window ideas\n\nSlide 1: A summer commuter bike with a basket of flowers.\nSlide 2: A wall of bright helmets.\nSlide 3: A chalkboard with the week's ride times."),

            item("i-front", "Shop front.jpg", .image, parent: "f-photos", size: 2_400_000, hours: 30),
            item("i-stock", "New stock.jpg", .image, parent: "f-photos", size: 3_100_000, hours: 31),
            item("i-bench", "Workbench.png", .image, parent: "f-photos", size: 860_000, hours: 72),

            item("p-march", "March receipts.pdf", .pdf, parent: "f-receipts", size: 540_000, hours: 700, body: "March receipts\n\nParts, tools and shop supplies for March."),
            item("p-april", "April receipts.pdf", .pdf, parent: "f-receipts", size: 610_000, hours: 400, body: "April receipts\n\nParts, tools and shop supplies for April."),
            item("t-order", "Parts order.txt", .text, parent: "f-receipts", size: 2_100, hours: 150,
                 body: "Parts order\n\n10 inner tubes, 700c\n6 brake pad sets\n4 chains, 11 speed\n2 bottles of chain oil"),

            item(opening, "Opening hours", .doc, hours: 6, starred: true, members: [owner, anyone],
                 body: "Opening hours\n\nMonday to Friday: 9 AM to 6 PM\nSaturday: 10 AM to 4 PM\nSunday: closed\n\nGroup ride leaves the shop at 8 AM on Saturdays."),
            item(rota, "Staff rota", .sheet, hours: 28, starred: true, members: [owner, mechanic]),
            item("o-event", "Event sign-up", .form, hours: 50),
            item("t-friday", "Notes for Friday.txt", .text, size: 1_200, hours: 1,
                 body: "Notes for Friday\n\nFinish the monthly report.\nCall the supplier about the late brake pads.\nPut the new helmets in the window."),
            item("i-logo", "Logo.png", .image, size: 120_000, hours: 500),

            item("d-old", "Old price list", .doc, hours: 300, trashed: true, body: "Old price list\n\nPrices from last year."),
            item("p-flyer", "Draft flyer.pdf", .pdf, size: 920_000, hours: 180, trashed: true, body: "Draft flyer\n\nSpring tune-up offer."),

            item("p-catalog", "Supplier catalog.pdf", .pdf, size: 5_600_000, hours: 80, shared: true,
                 body: "Supplier catalog\n\nTyres, tubes, chains, brake parts and tools. Prices before tax."),
            item("d-ride", "Group ride plan", .doc, hours: 40, shared: true,
                 body: "Group ride plan\n\nMeet at the shop at 8 AM. A flat 30 km loop with a coffee stop halfway."),
            item("s-prices", "Parts prices", .sheet, parent: "f-supplier", hours: 60, shared: true),
        ]
        for index in list.indices {
            list[index].sheets = sheets(for: list[index].id)
            list[index].form = form(for: list[index].id)
        }
        return list
    }

    private static func sheets(for id: String) -> [DriveSheetTab] {
        switch id {
        case inventory:
            return [
                DriveSheetTab(title: "Bikes", cells: [
                    ["Model", "Size", "Colour", "Stock", "Price"],
                    ["City commuter", "M", "Green", "4", "540"],
                    ["City commuter", "L", "Grey", "2", "540"],
                    ["Trail runner", "M", "Orange", "3", "890"],
                    ["Kids 20 inch", "S", "Blue", "6", "260"],
                    ["Road light", "L", "Black", "1", "1200"],
                ]),
                DriveSheetTab(title: "Parts", cells: [
                    ["Part", "Stock", "Reorder at"],
                    ["Inner tube 700c", "18", "10"],
                    ["Brake pads", "5", "8"],
                    ["Chain 11 speed", "7", "4"],
                ]),
            ]
        case "s-sales":
            return [DriveSheetTab(title: "2026", cells: [
                ["Month", "Bikes", "Repairs", "Total"],
                ["July", "14", "38", "9200"],
                ["August", "16", "41", "10350"],
                ["September", "12", "39", "8400"],
            ])]
        case "s-repairs":
            return [DriveSheetTab(title: "Log", cells: [
                ["Date", "Bike", "Job", "Status"],
                ["Mon", "Trail runner", "Brake bleed", "Done"],
                ["Tue", "City commuter", "New chain", "Done"],
                ["Wed", "Kids 20 inch", "Flat tyre", "Waiting"],
            ])]
        case rota:
            return [DriveSheetTab(title: "This week", cells: [
                ["Day", "Morning", "Afternoon"],
                ["Monday", "Sam", "Alex"],
                ["Tuesday", "Alex", "Jo"],
                ["Wednesday", "Jo", "Sam"],
                ["Thursday", "Sam", "Alex"],
                ["Friday", "Alex", "Jo"],
            ])]
        case "s-prices":
            return [DriveSheetTab(title: "Prices", cells: [
                ["Part", "Price"],
                ["Inner tube 700c", "6"],
                ["Brake pads", "14"],
                ["Chain 11 speed", "32"],
            ])]
        default:
            return []
        }
    }

    private static func form(for id: String) -> DriveForm? {
        switch id {
        case survey:
            return DriveForm(
                title: "Customer survey",
                questions: [
                    DriveQuestion(text: "How did you hear about us?", type: .choice, choices: ["A friend", "Online", "Walked past"]),
                    DriveQuestion(text: "What did we fix?", type: .short),
                    DriveQuestion(text: "Anything we could do better?", type: .paragraph),
                ],
                published: true,
                responses: [
                    "Online · Brakes · Booking online would help",
                    "A friend · New chain · All good",
                    "Walked past · Flat tyre · Open earlier on Saturdays",
                ]
            )
        case "o-event":
            return DriveForm(
                title: "Event sign-up",
                questions: [
                    DriveQuestion(text: "Your name", type: .short),
                    DriveQuestion(text: "Which ride?", type: .checkboxes, choices: ["Saturday group ride", "Kids skills day"]),
                ]
            )
        default:
            return nil
        }
    }
}

nonisolated extension DriveMember {
    /// The same member with a different access level.
    func with(_ access: DriveAccess) -> DriveMember {
        var copy = self
        copy.access = access
        return copy
    }
}
