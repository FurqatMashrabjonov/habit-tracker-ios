# HabitDots handoff — 2026-10-19

Where both apps stand, what was decided, and what comes next. Same file in both repos.

## Repos and environment

| | Android | iOS |
|---|---|---|
| Repo | `github.com/FurqatMashrabjonov/habit-tracker` | `github.com/FurqatMashrabjonov/habit-tracker-ios` |
| Local path | `~/apps/habit/habit` | `~/apps/habit/habit-tracker-ios` |
| Stack | Kotlin, Compose, Room v8 | SwiftUI, GRDB (same schema), XcodeGen (`project.yml`) |
| Build | `./gradlew :app:installDebug` | `xcodegen generate` then `xcodebuild -project HabitDots.xcodeproj -scheme HabitDots -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` |
| Tests | `./gradlew :app:testDebugUnitTest` | `cd Packages/HabitKit && swift test` |

- **Firebase project** `habitdots-app`: Auth (Google only), Firestore `users/{uid}/habits`, `months`; Crashlytics (crash logs only, release builds). No Analytics.
- **Gitignored secrets**: `app/google-services.json` (Android) and `HabitDots/GoogleService-Info.plist` (iOS). Both are present on this machine. The Android upload keystore is in `~/.config/habitdots/`.
- **iOS signing**: `DEVELOPMENT_TEAM` is not set in `project.yml`; there is no Apple Developer account yet.
- **Debug hooks**: iOS launch args `-demo`, `-paywall`, `-pretendPro YES|NO`, `-open <id>`, `-restore <path>`, `-settings`, `-inbox`, `-add`, `-onb <step>`. Android debug: Settings → "Pretend Pro".
- **Installing a debug build beside the Play build** (Android): an init script that sets `applicationIdSuffix = '.preview'` on the debug build type gives `app.habitdots.preview` (its Firebase client exists in `google-services.json`). With `Pretend Pro` on and an account signed in, that build syncs to the real account: keep Pro off, or sign out, when loading test data.
- Shared Room/GRDB schema: `tracker`, `entry` (value −1 = rest day), `task` (priority 1–4, 4 = none), `note`, `tombstone`, `trash`; `PRAGMA user_version = 8`. Backups restore across platforms (verified both ways, again on 2026-10-19).

## Pro and pricing (decided 2026-10-19, in the code)

- **Free**: tracking, every widget (all three kinds, every layout and row style, the Paper/Night look), every card style in the app, reminders, notes, Inbox, backup/restore/CSV, share cards — with up to **4 habits**. Never gate the user's own data.
- **Pro** (four paywall tiles): **unlimited habits**, **evening check-in**, **home screen looks**, **sync**. Decided 2026-10-19 after the widget research: widgets stay free and fully working, their *looks* are Pro. Strictly black, white and grey: looks differ by type, dot shape, frame, texture and composition, never colour.
  - *Home screen looks*: widget looks Clear, Glass, Terminal, Dot matrix, E-ink, Outline, Receipt; dot shapes Round and Pixel; app icons Night, Mono, Dots. Android: `Look.pro`, `palette()` falls back to Paper/Night without Pro, Save in widget settings opens the paywall (`WidgetSettingsActivity`); dots get an ink (`DotInk`: outline rings, LED glow) and the card a border/receipt header (`WidgetStyle.kt`). iOS: `WidgetLook.pro`, `WidgetPalette.resolve` falls back when `Shared.pro` is false (the app writes that file in `Store.publish`); `InkedCells`, `WidgetBars` in HabitDesign; bundled fonts DotGothic16 (2 MB, full CJK set, could be subset) and VT323 in `Shared/Fonts`. ponytail: Glance text can't use a bundled font, so on Android Dot matrix and Receipt keep system fonts and the dots carry the look.
  - New free layouts: Streak now a big number over the last 14 days; Bars (one bar per week) on the single-habit widget.
  - Wave 2 (not built): Pixel, Typewriter, Negative, Serif looks; backlog Graph, Frame, Hatched, Ledger. Research and gallery: https://claude.ai/artifact/MCjMPA4E4oM6nPTAb5s1VG · https://claude.ai/artifact/LYrtVRCpmt1nTtsQbkdRf1 · shortlist and plan https://claude.ai/artifact/B8YGuDSx1cdmXYhRxyc9XA
  - *Evening check-in*: one notification at a chosen time (21:00 by default), only when some of today's habits are still open; nothing on days everything is done. Android decides at fire time (`task/EveningNudge.kt`). iOS schedules the next three evenings with the reminders and rebuilds them on every change; a check from a widget or a notification's Done redoes tonight's (`Shared/Nudge.swift`, `ReminderPlan.nudges`).
  - *App icons* (inside Home screen looks): Paper (default), Night, Mono, Dots. Android: one `activity-alias` per icon, exactly one enabled (`util/AppIcon.kt`); the launcher entry moved from `MainActivity` to `.IconPaper`, so testers' home-screen shortcuts may need re-adding once. iOS: alternate icon sets `AppIcon-*` with `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`.
  - Signed in but Pro lapsed: the Sync page says sync is paused and offers Pro.
- **Prices** (set by hand in the stores): Yearly **$7.99** with a 7-day trial (default choice), Lifetime **$19.99** as the hero, launch price **$14.99** until ~2027-01-31. No monthly. Regional prices by purchasing power: BR/TR/MX/KZ ~50%, IN/ID ~35%, UZ ~25–30% of the US price. Research and the full table: see the Pro research in the 2026-10-19 session.
- **Next Pro candidates** (not built): sections (Morning/Evening), a year wall with a "2026 in dots" share card before the new year, later a web version.

## Onboarding (upgraded 2026-10-19, both platforms)

Four steps on the existing animated flow: 1 the deck of cards, 2 pick habits (a "Your own" chip comes first and turns into a text field; typed habits join the picks), 3 **first dot**: "Did you read 20 pages today?" ("No sugar today?", "Gym today?" for "No ..." and typed habits); the box or "Done it today" saves a real entry so home opens at 1/N, 4 the widgets, then "Remind me at 08:00 / 21:00 / Never" (21:00 default) for every picked habit; notification permission asked on the last tap. **No Pro anywhere in onboarding** (user's rule): no looks step, no free-limit text; the 4-habit limit holds silently under "Fewer is easier to keep." Monochrome only: the streak line uses the app's flame icon, no emoji. The only Pro touch left is "I already use HabitDots", since sign-in sync is Pro.

## QA on 2026-10-19 (Samsung S22 + iPhone 17 Pro simulator)

Every flow was driven by script with screenshots: onboarding, home, detail, Inbox, Settings, widgets, backup/CSV, trash, time travel (midnight, +10 days, +1 month, +1 year, clock back), 40 habits with long/RTL/emoji names, 200 tasks, dark mode, large text. Plan: https://claude.ai/artifact/Thdxs8jsXEhLq3pD85CmkU

Fixed on both platforms: "Complete yesterday" only added one to a counter; a tap on a done counter raised it invisibly past the target (now clears like a check); restoring from Recently deleted skipped the free limit; "Don't miss today!" stayed after the streak was gone; an auto-backup date left in the future stopped automatic copies; old dates now show their year; share cards carry "HabitDots". Android only: weekday chips wrapped "Mo"/"We"; widgets showed yesterday for up to an hour after midnight without exact-alarm access (now a 10-minute window); the checklist widget shows "+N more"; heatmap month labels no longer run into the dots at large text. iOS only: a card stayed faded after its long-press menu (onDrag ran with no drop).

Release-build performance (Android, 40 habits, a year of history): cold start 100–260 ms, 2% janky frames while scrolling, 143 MB.

## Store and payout facts

- **Google Play**: payouts approved to the Uzum Bank USD account (2026-10-19). Products `pro_yearly` (base plan `yearly`, 7-day trial) and `pro_lifetime` exist. The 15% service fee needs enrolling.
- **App Store**: IAP via StoreKit; 15% after enrolling in the Small Business Program. Uzbekistan is a storefront; pay the $99 with an international card. For payouts try Uzum Bank USD first under Agreements → Banking, else Payoneer/Wise. Fill W-8BEN.
- **Play closed testing** started 2026-10-16 (opt-in https://play.google.com/apps/testing/app.habitdots). **Apply for production on or after 2026-10-30.** 1.0.1 (versionCode 3, Google sign-in fix) was never uploaded: ship everything since in the production build with a new versionCode. The data-safety form must declare crash logs (Crashlytics).

## Next steps, in order

1. Store setup by hand: Play 15% enrolment, new prices and regional prices in both stores, store descriptions for the new Pro.
2. On/after 2026-10-30: Android production release (new versionCode, data safety, prices).
3. iOS: Apple Developer account → `DEVELOPMENT_TEAM` → TestFlight; then check the widgets and the widget-side check-in refresh on a signed build (the unsigned simulator can't).
4. Check by hand: drag-to-reorder on both phones (the iOS fix touched it).
5. Open test issues: `HabitDotsTests/StoreTests` fails on this Mac's Xcode 27 StoreKit setup (also on commits from before 2026-10-19); `androidTrashSnapshotReads` in HabitKit is flaky.
6. Queued for the next phase (asked 2026-10-19): where the Inbox priority flag and ordering sit on widgets and the home screen; a different design for choosing views (card-style picker and widget look picker as one "looks" gallery, not a settings list). Done since: the paywall with live feature tiles, the onboarding upgrade.
7. Smaller notes: the note field is a single line; CSV export leaves out counter values and rest days; unsaved edits are lost if Android kills the app; a database with an invalid time crashes on launch (only reachable through a hand-made file).

## Artifacts (private, claude.ai)

- QA plan 2026-10-19: https://claude.ai/artifact/Thdxs8jsXEhLq3pD85CmkU
- QA report with screenshots (2026-10-17): https://claude.ai/artifact/2vvVdYZj6sTdJKdHi1z7Ur
- Habit card view variants: https://claude.ai/artifact/1V59pt4oT3oKQ5vgp5cTkr
- Habits header variants (card-style button placement, still open): https://claude.ai/artifact/Y8zpnzyVrRnkCcCuDdE9b2
