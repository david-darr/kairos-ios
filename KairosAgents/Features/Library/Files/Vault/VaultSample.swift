import Foundation

/// A made-up vault for a small bike shop and a weekly report. Nothing here is real.
nonisolated enum VaultSample {
    private static func note(_ id: String, hoursAgo: Double, by: String = "you", _ body: String) -> VaultNote {
        VaultNote(id: id, body: body, edited: Date.now.addingTimeInterval(-hoursAgo * 3600), editedBy: by)
    }

    static func notes() -> [VaultNote] {
        var all: [VaultNote] = [
            note("Home", hoursAgo: 30, """
            ---
            type: index
            status: active
            project: Vault
            ---
            # Home

            The front door of this vault. Start with what is open this week.

            - [[Launch plan]] for the bike shop
            - [[Weekly report]] is due Friday
            - [[Video ideas]] for the content team
            - [[Reading list]]
            """),
            note("Projects/Projects", hoursAgo: 52, """
            ---
            type: index
            status: active
            project: Vault
            ---
            # Projects

            - [[Bike shop]]
            - [[Weekly report]]
            - [[Raised bed plan]]
            """),
            note("Projects/Bike shop/Bike shop", hoursAgo: 26, """
            ---
            type: index
            status: active
            project: Bike shop
            ---
            # Bike shop

            Everything for the spring opening.

            - [[Launch plan]]
            - [[Rival prices]]
            - [[Booking page brief]]
            - [[Opening day checklist]]
            """),
            note("Projects/Bike shop/Launch plan", hoursAgo: 3, by: "Kairos", """
            ---
            status: active
            project: Bike shop
            type: plan
            ---
            # Launch plan

            The shop opens on the first Saturday of spring. This page holds the plan; the numbers live in [[Rival prices]].

            ## This week

            - [x] Pick the opening date
            - [x] Ask Scout for three rival price lists
            - [ ] Approve the [[Booking page brief]]
            - [ ] Order the window sign

            ## Pricing

            Tune-ups start at the middle of the local range. A full service stays a little under the nearest rival.

            | Service | Ours | Nearest rival |
            | --- | --- | --- |
            | Basic tune-up | 45 | 50 |
            | Full service | 95 | 110 |
            | Flat repair | 12 | 15 |

            > [!note] Open question
            > Do we offer a student discount in the first month?

            ## Opening day

            1. Doors open at 9
            2. Free safety checks until noon
            3. Raffle for a helmet at 4

            See [[Opening day checklist]] and ask the supplier list in [[Supplier contacts]].

            ```
            hours: Tue-Sat 9-6
            phone line: set up by Friday
            ```

            ![[Booking page brief]]
            """),
            note("Projects/Bike shop/Rival prices", hoursAgo: 28, by: "Kairos", """
            ---
            status: done
            project: Bike shop
            type: research
            ---
            # Rival prices

            Three shops within a short ride. Scout collected the lists on Tuesday.

            - North street shop: tune-up 50, full service 110
            - Riverside cycles: tune-up 55, full service 120
            - Corner repairs: tune-up 40, flat repair 15

            Used in the [[Launch plan]].
            """),
            note("Projects/Bike shop/Booking page brief", hoursAgo: 20, """
            ---
            status: review
            project: Bike shop
            type: brief
            ---
            # Booking page brief

            One page where a rider picks a service and a time.

            - Big service buttons with prices from [[Rival prices]]
            - A calendar with open slots
            - A short form: name, phone, bike type

            **Tone:** friendly, short sentences, no jargon.
            """),
            note("Projects/Bike shop/Opening day checklist", hoursAgo: 70, """
            ---
            status: active
            project: Bike shop
            type: checklist
            ---
            # Opening day checklist

            - [x] Balloons
            - [ ] Float for the till
            - [ ] Helmet for the raffle
            - [ ] Coffee for the first hour

            Back to the [[Launch plan]].
            """),
            note("Projects/Weekly report/Weekly report", hoursAgo: 8, """
            ---
            status: active
            project: Weekly report
            type: index
            ---
            # Weekly report

            Due Friday. Kip is drafting it from this week's notes.

            - [[Report outline]]
            - [[Sources]]
            """),
            note("Projects/Weekly report/Report outline", hoursAgo: 5, by: "Kairos", """
            ---
            status: draft
            project: Weekly report
            type: outline
            ---
            # Report outline

            ## Sections

            1. What happened this week
            2. What is blocked
            3. What comes next

            ### Notes for Kip

            - Keep it to one page
            - Use the numbers from [[Sources]]
            - *Mention* the opening date from the [[Launch plan]]
            """),
            note("Projects/Weekly report/Sources", hoursAgo: 46, """
            ---
            status: active
            project: Weekly report
            type: research
            ---
            # Sources

            Two sources Scout found for the project, plus one from last week.

            - A guide to small shop budgets
            - A survey of local riders
            - Last week's [[Report outline]]
            """),
            note("Projects/Garden/Raised bed plan", hoursAgo: 120, """
            ---
            status: paused
            project: Garden
            type: plan
            ---
            # Raised bed plan

            A 4 by 8 bed with room for tomatoes, beans and herbs. Seeds are in [[Seed order]].
            """),
            note("Projects/Garden/Seed order", hoursAgo: 150, """
            ---
            status: done
            project: Garden
            ---
            # Seed order

            - [x] Tomatoes
            - [x] Runner beans
            - [ ] Basil

            For the [[Raised bed plan]].
            """),
            note("Ideas/Video ideas", hoursAgo: 14, by: "Kairos", """
            ---
            status: active
            project: Content
            type: ideas
            ---
            # Video ideas

            Ideas for the content team, newest first.

            - Fixing a flat in under two minutes
            - What a tune-up really includes
            - A ride along the river path, see [[Weekend trips]]
            - Behind the counter on opening day ([[Launch plan]])
            """),
            note("Ideas/Shop names", hoursAgo: 400, """
            ---
            status: done
            project: Bike shop
            type: ideas
            ---
            # Shop names

            - Spoke and Chain
            - The Quiet Gear
            - Second Wind Cycles

            We picked the first one for the [[Bike shop]].
            """),
            note("Ideas/Weekend trips", hoursAgo: 90, """
            ---
            project: Personal
            ---
            # Weekend trips

            Two routes, both under four hours. The river path is flat; the hill loop has a café at the top.
            """),
            note("Reference/Repair basics", hoursAgo: 300, """
            ---
            status: active
            project: Bike shop
            type: reference
            ---
            # Repair basics

            ## Flat tyre

            1. Take the wheel off
            2. Find the hole with water
            3. Patch, wait, refit

            ## Brakes

            Check the pads first. Worn pads cause most squeaks.
            """),
            note("Reference/Reading list", hoursAgo: 200, """
            ---
            status: active
            project: Personal
            type: reference
            ---
            # Reading list

            - A book about running a small shop
            - A field guide to garden pests, for the [[Raised bed plan]]
            """),
            note("Reference/Markdown cheat sheet", hoursAgo: 900, """
            # Markdown cheat sheet

            **Bold**, *italic*, `code`, and a [link](https://example.com).

            - A list item
            - [ ] A checkbox

            > A quote
            """),
            note("Templates/Daily note", hoursAgo: 1000, """
            ## Today

            - [ ]

            ## Notes

            """),
            note("Inbox/Loose thought", hoursAgo: 2, """
            Maybe a loyalty card: every fifth tune-up free.
            """),
        ]

        let calendar = Calendar.current
        let days: [(Int, String)] = [
            (1, "Called two suppliers. Prices are in the [[Launch plan]]."),
            (2, "Kip drafted the [[Report outline]]. Scout is on [[Sources]]."),
            (3, "Walked the river path for [[Video ideas]]."),
            (5, "Paid the deposit for the shop sign."),
            (8, "Picked the opening date. See [[Launch plan]]."),
            (12, "Planted the first seeds. [[Seed order]] is done."),
            (20, "Quiet day."),
            (33, "Started the [[Bike shop]] project."),
        ]
        var indexLines: [String] = []
        for (offset, text) in days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let title = VaultDates.dailyTitle(date)
            all.append(VaultNote(
                id: "Daily notes/\(title)",
                body: "---\ntype: daily\n---\n# \(title)\n\n## Today\n\n- [x] Check the shop email\n\n## Notes\n\n\(text)\n",
                edited: date.addingTimeInterval(18 * 3600),
                editedBy: "you"
            ))
            indexLines.append("- [[\(title)]]")
        }
        all.append(VaultNote(
            id: "Daily notes/Daily notes",
            body: "---\ntype: index\nstatus: active\nproject: Vault\n---\n# Daily notes\n\nOne note a day, newest first.\n\n" + indexLines.joined(separator: "\n") + "\n",
            edited: Date.now.addingTimeInterval(-86_400),
            editedBy: "you"
        ))
        return all
    }

    static func history(_ notes: [String: VaultNote]) -> [String: [VaultChange]] {
        var result: [String: [VaultChange]] = [:]
        for (id, note) in notes {
            let created = VaultChange(date: note.edited.addingTimeInterval(-86_400 * 3), label: "Created", by: "you", before: "", after: note.body)
            result[id] = [created]
        }
        if let plan = notes["Projects/Bike shop/Launch plan"] {
            let older = plan.body.replacingOccurrences(of: "- [ ] Order the window sign\n", with: "")
            result[plan.id] = [
                VaultChange(date: plan.edited, label: "+1 −0", by: "Kairos", before: older, after: plan.body),
                VaultChange(date: plan.edited.addingTimeInterval(-86_400), label: "Outside Kairos", by: "outside Kairos", before: older, after: older),
                VaultChange(date: plan.edited.addingTimeInterval(-86_400 * 4), label: "Created", by: "you", before: "", after: older),
            ]
        }
        return result
    }
}
