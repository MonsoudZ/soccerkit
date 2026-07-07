import Foundation

/// Seed data used on first launch, for previews, and by "Reset to sample data".
enum SampleData {
    static var snapshot: AppSnapshot {
        let u12 = Team(
            id: UUID(uuidString: "B78D1E06-3270-498F-A763-28C26EF5A001")!,
            name: "Northside Falcons",
            ageGroup: .u12,
            season: "Fall 2026",
            accentName: "Teal",
            trainingDefaults: TrainingBoardDefaults(playerCount: 8, opponentCount: 4, coneCount: 10, zoneCount: 1)
        )

        let u10 = Team(
            id: UUID(uuidString: "B78D1E06-3270-498F-A763-28C26EF5A002")!,
            name: "Park United",
            ageGroup: .u10,
            season: "Fall 2026",
            accentName: "Orange",
            trainingDefaults: TrainingBoardDefaults(playerCount: 6, opponentCount: 2, coneCount: 8, zoneCount: 1)
        )

        let players = [
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810001")!, teamID: u12.id, name: "Maya Chen", number: 2, position: .defender, guardian: "Alex Chen", notes: "Excellent recovery speed.", guardianPhone: "555-0142", guardianEmail: "alex.chen@example.com", secondaryContactName: "Jo Chen", secondaryContactPhone: "555-0143", emergencyContactName: "Alex Chen", emergencyContactPhone: "555-0142", emergencyContactRelation: "Parent", allergies: "Peanuts", medicalNotes: "Carries an EpiPen in her kit bag."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810002")!, teamID: u12.id, name: "Sofia Ramirez", number: 7, position: .midfielder, guardian: "Nina Ramirez", notes: "Working on scanning before first touch.", developmentLog: [
                DevelopmentEntry(date: Date().addingTimeInterval(-30 * 86400), notes: "Starting to check her shoulder before receiving. Passing range is a real strength.", ratings: ["Technical": 3, "Passing": 4, "Tactical": 2, "Attitude": 4]),
                DevelopmentEntry(date: Date().addingTimeInterval(-7 * 86400), notes: "Scanning is more consistent now and first touch out of her feet has improved.", ratings: ["Technical": 4, "Passing": 4, "Tactical": 3, "Attitude": 5])
            ]),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810003")!, teamID: u12.id, name: "Ava Patel", number: 9, position: .forward, guardian: "Dev Patel", notes: "Confident finisher, encourage combination play."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810004")!, teamID: u12.id, name: "Lena Brooks", number: 10, position: .midfielder, guardian: "Morgan Brooks", notes: "Captain this month."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810005")!, teamID: u12.id, name: "Grace Kim", number: 12, position: .goalkeeper, guardian: "Sam Kim", notes: "Add distribution reps every week.", guardianPhone: "555-0188", guardianEmail: "sam.kim@example.com", emergencyContactName: "Pat Kim", emergencyContactPhone: "555-0189", emergencyContactRelation: "Grandparent", allergies: "None", medicalNotes: "Mild asthma - keeps an inhaler on the bench."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810008")!, teamID: u12.id, name: "Nora Allen", number: 14, position: .defender, guardian: "Chris Allen", notes: "Strong 1v1 defender."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810009")!, teamID: u12.id, name: "Zoe Martin", number: 15, position: .midfielder, guardian: "Rae Martin", notes: "Good passing range."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810010")!, teamID: u12.id, name: "Isla Nguyen", number: 17, position: .forward, guardian: "Minh Nguyen", notes: "Encourage defensive pressing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810011")!, teamID: u12.id, name: "Emma Davis", number: 18, position: .defender, guardian: "Taylor Davis", notes: "Reliable on restarts."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810012")!, teamID: u12.id, name: "Layla Moore", number: 21, position: .midfielder, guardian: "Harper Moore", notes: "Develop left-foot passing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810013")!, teamID: u12.id, name: "Ruby Scott", number: 23, position: .forward, guardian: "Jordan Scott", notes: "Quick off the mark."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810014")!, teamID: u12.id, name: "Mila Young", number: 24, position: .defender, guardian: "Casey Young", notes: "Learning center back spacing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810006")!, teamID: u10.id, name: "Noah Wilson", number: 4, position: .defender, guardian: "Jules Wilson", notes: "New to the team."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810007")!, teamID: u10.id, name: "Eli Carter", number: 8, position: .midfielder, guardian: "Tess Carter", notes: "Loves small-sided games.")
        ]

        let rondo = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00001")!,
            teamID: nil,
            title: "4v1 Rondo",
            category: .technical,
            tags: ["possession", "first touch", "passing"],
            durationMinutes: 12,
            equipment: ["Four cones", "One ball", "Two spare balls"],
            fieldSize: "10x10 yards",
            fieldSetup: "10x10 yard grid, one defender, four attackers.",
            coachingPoints: ["Open body shape", "Pass with pace", "Move after the pass"],
            progressions: ["Limit attackers to two touches", "Add a second defender after five passes"],
            regressions: ["Make the grid larger", "Allow unlimited touches"]
        )

        let finishing = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00002")!,
            teamID: u12.id,
            title: "Wide Service Finishing",
            category: .technical,
            tags: ["finishing", "wide play", "crossing"],
            durationMinutes: 18,
            equipment: ["Cones", "Full-size goal", "Supply of balls", "Bibs"],
            fieldSize: "Penalty area plus wide channels",
            fieldSetup: "Two wide channels, two central finishers, one goalkeeper.",
            coachingPoints: ["Arrive on time", "Attack near and far posts", "Follow rebounds"],
            progressions: ["Add a recovering defender", "Require one-touch finishes"],
            regressions: ["Serve unopposed crosses", "Start finishers closer to goal"]
        )

        let pressureCover = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00003")!,
            teamID: u12.id,
            title: "Pressure and Cover",
            category: .tactical,
            tags: ["defending", "pressure", "cover"],
            durationMinutes: 15,
            equipment: ["Cones", "Two small goals", "Bibs", "Balls"],
            fieldSize: "20x25 yards",
            fieldSetup: "20x25 yard channel with two defenders and three attackers.",
            coachingPoints: ["First defender presses", "Second defender covers angle", "Recover goal side"],
            progressions: ["Add transition goals after a defensive win", "Reduce the channel width"],
            regressions: ["Start attackers from a static pass", "Give defenders an extra recovery player"]
        )

        let game = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00004")!,
            teamID: nil,
            title: "5v5 to End Zones",
            category: .scrimmage,
            tags: ["transition", "width", "small-sided"],
            durationMinutes: 20,
            equipment: ["Cones", "Bibs", "Balls"],
            fieldSize: "Half field",
            fieldSetup: "Half field, two end zones, score by receiving in the zone.",
            coachingPoints: ["Create width", "Look forward first", "Transition quickly"],
            progressions: ["Score must come from a third-player run", "Limit neutral players to one touch"],
            regressions: ["Add neutral support players", "Increase end-zone depth"]
        )

        let attendance: [UUID: AttendanceStatus] = [
            players[0].id: .present,
            players[1].id: .present,
            players[2].id: .late,
            players[3].id: .excused,
            players[4].id: .present
        ]

        let session = TrainingSession(
            id: UUID(uuidString: "A81EE2E0-46A5-408D-9A93-9AE0AF870001")!,
            teamID: u12.id,
            title: "Building Through Midfield",
            date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
            objective: "Improve first touch, support angles, and quick transitions after winning the ball.",
            blocks: [
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900001")!, drillID: rondo.id, minutes: 12, focus: "First touch away from pressure"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900002")!, drillID: pressureCover.id, minutes: 15, focus: "Win it, connect the next pass"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900003")!, drillID: game.id, minutes: 20, focus: "Use width to break pressure")
            ],
            attendance: attendance
        )

        let secondSession = TrainingSession(
            id: UUID(uuidString: "A81EE2E0-46A5-408D-9A93-9AE0AF870002")!,
            teamID: u12.id,
            title: "Final Third Decisions",
            date: Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date(),
            objective: "Help attackers choose between shooting, crossing, and recycling possession.",
            blocks: [
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900004")!, drillID: rondo.id, minutes: 10, focus: "Fast rhythm"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900005")!, drillID: finishing.id, minutes: 18, focus: "Timing runs into the box"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900006")!, drillID: game.id, minutes: 22, focus: "Reward correct final pass")
            ],
            attendance: [:]
        )

        let leagueGame = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0001")!,
            teamID: u12.id,
            opponent: "Riverside Rovers",
            date: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date(),
            location: "Central Park Field 3",
            isHome: true,
            notes: "League fixture. Arrive 45 minutes early for warm-up.",
            rsvps: [
                players[0].id: .going,
                players[1].id: .going,
                players[2].id: .maybe,
                players[3].id: .notGoing,
                players[4].id: .going
            ],
            // Maya is set to play but reported a tight hamstring and poor sleep —
            // the availability board should flag her for a look.
            preMatchCheckIns: [
                players[0].id: PreMatchCheckIn(sleep: 2, energy: 2, freshness: 3, hydration: 3,
                                               nutrition: 2, mood: 3, composure: 2, focus: 2,
                                               hasPain: true, note: "Tight hamstring warming up.")
            ]
        )

        let awayGame = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0002")!,
            teamID: u12.id,
            opponent: "Hilltop Hawks",
            date: Calendar.current.date(byAdding: .day, value: 11, to: Date()) ?? Date(),
            location: "Hilltop Sports Complex",
            isHome: false,
            notes: "Carpool sign-up to follow.",
            rsvps: [:]
        )

        let playedHome = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0003")!,
            teamID: u12.id,
            opponent: "Maple Strikers",
            date: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
            location: "Central Park Field 3",
            isHome: true,
            notes: "Controlled the midfield and finished our chances.",
            attendance: [
                players[0].id: .present, players[1].id: .present, players[2].id: .present,
                players[3].id: .present, players[4].id: .late
            ],
            teamScore: 3,
            opponentScore: 1,
            playerReports: [
                players[2].id: GamePlayerReport(minutes: 60, goals: 2, assists: 0, effort: 5, developmentFocus: "Movement in the box"),
                players[1].id: GamePlayerReport(minutes: 55, goals: 1, assists: 1, effort: 4),
                players[3].id: GamePlayerReport(minutes: 50, goals: 0, assists: 1, effort: 4)
            ],
            // Ava was fresh and slept well before her best game.
            preMatchCheckIns: [
                players[2].id: PreMatchCheckIn(sleep: 5, energy: 5, freshness: 4, hydration: 4, nutrition: 5, mood: 5, composure: 4, focus: 5, warmedUp: true, hasPain: false)
            ],
            coachPreMatch: CoachPreMatchPlan(objective: "Control midfield tempo", keyMatchup: "Their #8 vs our press", focusPoints: "Quick switches, win second balls", watchFor: "Their pace on the counter"),
            coachPostMatch: CoachPostMatchReview(teamPerformance: 5, whatWorked: "Pressing traps in wide areas", whatToAdjust: "Tighter marking on set pieces", standoutPlayer: "Ava Patel")
        )

        let playedAway = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0004")!,
            teamID: u12.id,
            opponent: "Cedar United",
            date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            location: "Cedar Fields",
            isHome: false,
            notes: "Battled hard for a point away from home.",
            attendance: [
                players[0].id: .present, players[1].id: .present, players[2].id: .present,
                players[3].id: .absent, players[4].id: .present
            ],
            teamScore: 2,
            opponentScore: 2,
            playerReports: [
                players[1].id: GamePlayerReport(minutes: 58, goals: 1, assists: 0, effort: 4),
                players[2].id: GamePlayerReport(minutes: 62, goals: 1, assists: 1, effort: 5)
            ],
            preMatchCheckIns: [
                players[2].id: PreMatchCheckIn(sleep: 4, energy: 4, freshness: 4, hydration: 4, nutrition: 4, mood: 4, composure: 4, focus: 4, warmedUp: true, hasPain: false)
            ],
            // Sofia turned an ankle late on — carries into next game's availability.
            postMatchReflections: [
                players[1].id: PostMatchReflection(exertion: 4, performance: 3, hadInjury: true,
                                                   workOn: "Rest the ankle; monitor this week.")
            ]
        )

        // An earlier game Ava played poorly after a bad night's sleep — this is
        // what makes the readiness insight ("sleep is the biggest difference")
        // show up on her profile.
        let playedEarlier = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0009")!,
            teamID: u12.id,
            opponent: "Riverside Rovers",
            date: Calendar.current.date(byAdding: .day, value: -17, to: Date()) ?? Date(),
            location: "Central Park Field 3",
            isHome: true,
            notes: "Flat performance — struggled to get going.",
            attendance: [
                players[0].id: .present, players[1].id: .present, players[2].id: .present,
                players[3].id: .present, players[4].id: .present
            ],
            teamScore: 0,
            opponentScore: 2,
            playerReports: [
                players[2].id: GamePlayerReport(minutes: 55, goals: 0, assists: 0, effort: 2, developmentFocus: "Sharper first step")
            ],
            preMatchCheckIns: [
                players[2].id: PreMatchCheckIn(sleep: 2, energy: 2, freshness: 3, hydration: 3, nutrition: 2, mood: 3, composure: 3, focus: 2, warmedUp: true, hasPain: false, note: "Up late the night before.")
            ]
        )

        let tournament = TeamEvent(
            id: UUID(uuidString: "D53A9C11-77E4-4B2A-9F0E-2C4A6B8D0001")!,
            teamID: u12.id,
            title: "Fall Classic Cup",
            kind: .tournament,
            date: Calendar.current.date(byAdding: .day, value: 18, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 19, to: Date()) ?? Date(),
            location: "Riverside Tournament Grounds",
            notes: "Three group games Saturday, knockout rounds Sunday. Bring both kits.",
            rsvps: [
                players[0].id: .going,
                players[1].id: .going,
                players[2].id: .going,
                players[3].id: .maybe
            ]
        )

        let teamSocial = TeamEvent(
            id: UUID(uuidString: "D53A9C11-77E4-4B2A-9F0E-2C4A6B8D0002")!,
            teamID: u12.id,
            title: "End of Season Pizza Night",
            kind: .social,
            date: Calendar.current.date(byAdding: .day, value: 25, to: Date()) ?? Date(),
            location: "Mario's Pizzeria",
            notes: "Awards and team photo. Families welcome."
        )

        // A few responses recorded through the generic evaluation engine, so the
        // form spine is demonstrably live from first launch. New scored flows
        // add instances like these instead of another struct on an entity.
        let formInstances: [FormInstance] = [
            // Sofia's most recent development review (context = development).
            FormInstance(
                templateID: FormTemplateCatalog.ID.developmentReview,
                context: .development,
                subject: .athlete(players[1].id),
                submittedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
                answers: [
                    .scale("Technical", 4), .scale("Passing", 4), .scale("Tactical", 3), .scale("Attitude", 5),
                    .text("notes", "Scanning is more consistent; first touch out of her feet has improved."),
                ]
            ),
            // Ava's pre-match check-in ahead of the upcoming league game.
            FormInstance(
                templateID: FormTemplateCatalog.ID.preMatchCheckIn,
                context: .preGame,
                subject: .athlete(players[2].id),
                contextRef: .game(leagueGame.id),
                answers: [
                    .scale("sleep", 5), .scale("energy", 4), .scale("freshness", 4), .scale("hydration", 4),
                    .scale("nutrition", 5), .scale("mood", 5), .scale("composure", 4), .scale("focus", 5),
                    .bool("warmedUp", true), .bool("hasPain", false),
                ]
            ),
        ]

        return AppSnapshot(
            teams: [u12, u10],
            players: players,
            drills: [rondo, finishing, pressureCover, game],
            sessions: [session, secondSession],
            diagrams: [],
            games: [playedEarlier, playedHome, playedAway, leagueGame, awayGame],
            events: [tournament, teamSocial],
            selectedTeamID: u12.id,
            formInstances: formInstances
        )
    }
}
