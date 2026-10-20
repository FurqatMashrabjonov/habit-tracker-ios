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
  - *Home screen looks*: widget looks Clear, Glass, Terminal, Dot matrix, E-ink, Outline, Receipt; dot shapes Round and Pixel. Android: `Look.pro`, `palette()` falls back to Paper/Night without Pro, Save in widget settings opens the paywall (`WidgetSettingsActivity`); dots get an ink (`DotInk`: outline rings, LED glow) and the card a border/receipt header (`WidgetStyle.kt`). iOS: `WidgetLook.pro`, `WidgetPalette.resolve` falls back when `Shared.pro` is false (the app writes that file in `Store.publish`); `InkedCells`, `WidgetBars` in HabitDesign; bundled fonts DotGothic16 (2 MB, full CJK set, could be subset) and VT323 in `Shared/Fonts`. ponytail: Glance text can't use a bundled font, so on Android Dot matrix and Receipt keep system fonts and the dots carry the look.
  - New free layouts: Streak now a big number over the last 14 days; Bars (one bar per week) on the single-habit widget.
  - Wave 2 (not built): Pixel, Typewriter, Negative, Serif looks; backlog Graph, Frame, Hatched, Ledger. Research and gallery: https://claude.ai/artifact/MCjMPA4E4oM6nPTAb5s1VG · https://claude.ai/artifact/LYrtVRCpmt1nTtsQbkdRf1 · shortlist and plan https://claude.ai/artifact/B8YGuDSx1cdmXYhRxyc9XA
  - *Evening check-in*: one notification at a chosen time (21:00 by default), only when some of today's habits are still open; nothing on days everything is done. Android decides at fire time (`task/EveningNudge.kt`). iOS schedules the next three evenings with the reminders and rebuilds them on every change; a check from a widget or a notification's Done redoes tonight's (`Shared/Nudge.swift`, `ReminderPlan.nudges`).
  - *App icon*: no longer a Pro choice (removed 2026-10-19); the artwork is the original one (tiles at x 45.75/51.25/56.75/62.25, tilted −12°). A centred version and a bigger iOS crop were tried the same day and reverted at the user's request. iOS: `AppIcon` has the original Paper icon, the original Night icon as its dark rendition and a tinted rendition (`tools/gen_app_icon.swift` writes only the tinted one), so it follows the home screen's icon style (Edit → Customize; Automatic follows dark mode). Android: launchers don't reload icons on a theme change (tried `drawable-night`; Pixel Launcher ignores it), so the monochrome layer is the theme-following path (Android 13+ themed icons). The launcher entry is `MainActivity` again, as in Play 1.0.
  - Signed in but Pro lapsed: the Sync page says sync is paused and offers Pro.
- **Prices** (set by hand in the stores): Yearly **$7.99** with a 7-day trial (default choice), Lifetime **$19.99** as the hero, launch price **$14.99** until ~2027-01-31. No monthly. Regional prices by purchasing power; the per-country table (what is actually in Play Console) is under "Prices" below — reuse it for the App Store.
- **Next Pro candidates** (not built): sections (Morning/Evening), a year wall with a "2026 in dots" share card before the new year, later a web version.

## Billing through RevenueCat (2026-10-19, both platforms)

Pro is one RevenueCat entitlement shared by both apps, so a purchase on either phone unlocks both once the user signs in with the same Google account.

- **Dashboard**: project **HabitDots** `proj0ae14c1e` (https://app.revenuecat.com/projects/0ae14c1e). Apps: Play `app.habitdots` (`app153e95cfcf`), App Store `app.habitdots` (`appbdc9ca5aec`), Test Store (`appc4b98ade81`). Entitlement `pro`. Products: Play `pro_yearly:yearly` and `pro_lifetime`; App Store and Test Store `pro_yearly` and `pro_lifetime` (Test Store prices $7.99 / $19.99). Offering `default` (current) with packages `$rc_annual` and `$rc_lifetime`.
- **Identity**: the RevenueCat app user ID is the Firebase uid. A Firebase auth-state listener calls `logIn(uid)` on sign-in and `logOut()` on sign-out or account deletion. Purchases made before signing in are anonymous and merge into the uid on the first sign-in.
- **Code**: same facades as before, only the internals changed. Android `billing/Pro.kt` (SDK `com.revenuecat.purchases:purchases` 10.28.1, Play Billing dependency removed). iOS `HabitDots/Store.swift` (SPM `purchases-ios-spm` 5.96.0 in `project.yml`). The paywall and every gate are untouched; `Shared.pro` still feeds the iOS widgets; "Pretend Pro" still works in debug.
- **Keys**: debug builds use the Test Store key (`test_…`), release builds the store keys (`goog_…`, `appl_…`). Test Store purchases show a "Test valid purchase" dialog and need no store account. Never ship a release built with the test key: the SDK crashes in production with it.
- **Verified 2026-10-19**: Test Store purchase of Lifetime on the Android emulator (anonymous user) and of Yearly on the iOS simulator (signed in, uid `038JVlA89ZaTo2jBaE9BIRza8Ga2`): both unlock Pro, and the dashboard shows the entitlement. **Not yet verified**: the same Google account on both phones getting Pro from one purchase (the emulator has no Google account). Check it on the S22 preview build signed into the account the simulator uses.
- **Play connected 2026-10-19**: service account `revenuecat@habitdots-app.iam.gserviceaccount.com` (Google Cloud project `habitdots-app`, owned by the Firebase account; roles: Pub/Sub Admin) has account-level Play Console access "View app information", "View financial data…" and "Manage orders and subscriptions"; its JSON key is uploaded in RevenueCat (no local copy kept) and all three RevenueCat credential checks are valid. APIs on: Android Publisher, Play Developer Reporting, Pub/Sub, IAM. RTDN: topic `projects/habitdots-app/topics/Play-Store-Notifications`, push subscription `RevenueCat-Subscriber-app153e95cfcf` → RevenueCat. Still open: App Store In-App Purchase key (.p8) and App Store Server Notifications once the Apple account exists.
- Free under $2,500 monthly tracked revenue, then 1%. Money still goes straight from Google and Apple to the bank.

## Onboarding (upgraded 2026-10-19, both platforms)

Four steps on the existing animated flow: 1 the deck of cards, 2 pick habits (a "Your own" chip comes first and turns into a text field; typed habits join the picks), 3 **first dot**: "Did you read 20 pages today?" ("No sugar today?", "Gym today?" for "No ..." and typed habits); the box or "Done it today" saves a real entry so home opens at 1/N, 4 the widgets, then "Remind me at 08:00 / 21:00 / Never" (21:00 default) for every picked habit; notification permission asked on the last tap.

User's rules for onboarding: **never mention or show Pro** (no looks step, no free-limit text; the 4-habit limit holds silently under "Fewer is easier to keep."), **no colour or emoji** (the streak line uses the app's flame icon), **users can type their own habit**. "I already use HabitDots" goes straight to Google sign-in with no paywall: a returning Pro user's purchase comes back from the store and sync (Pro only, `Sync.kt`) brings the habits; a non-Pro user just lands in the app, and Settings → Sync says sync is paused.

## Other changes on 2026-10-19 (afternoon)

- **Settings → Appearance** shows only the app theme (System/Light/Dark). Card styles are on the home screen; widget light/dark is in each widget's settings (Android).
- **Card style button** moved next to the add button, a round header button like Settings whose icon is the style in use (wall / four squares / rows). The picker has no frames or checkboxes: each style's real card sits on its own grey slab (darker with an "In use" tag for the current one); one tap picks and closes.
- **Year in dots on the lock screen (Android, 2026-10-20)**: Settings → Lock screen. A plain image set with `FLAG_LOCK` (the home screen keeps its wallpaper; the user rejected dots behind widgets), 20 dots a row, the days gone filled, today ringed, "293 / 365 · 80%" under it, centred on the screen (37–66% of the height) so it clears the clock above and the in-display fingerprint sensor below; Dark or Light. Redrawn at the midnight refresh and on app start if a day was missed (`util/LockWallpaper.kt`, bump `LAYOUT` when the drawing changes). Turning it off clears the lock wallpaper, so the home wallpaper shows there; a separate earlier lock wallpaper can't be restored. Each past day's dot is as dark as the share of habits done that day (rest days excluded; days before any habit existed look like future days), the label says "2/3 today · 293 / 365", and it redraws on every check (from `WidgetRefresh.now`) but only when the picture changed (a stamp of the levels). Lock screen widgets were tried and dropped (2026-10-20): One UI 8 lists only Samsung's own widgets and LockStar didn't offer HabitDots either, so the widgets stay `home_screen` only and the wallpaper is the lock screen presence. Looks (2026-10-20): eight presets (Classic, Calendar, Months, Ring, Dot matrix, Outline, E-ink, Serif) and every option on its own row — layout (grid with the last row centred, since 365 = 5 × 73; a row per month; twelve mini months; a ring), dot shape, fill, what it shows (all habits, one habit, the year), background, font (bundled VT323, DotGothic16, Instrument Serif), size, words (incl. your own text). Edited full screen like the phone's own lock screen editor (`ui/settings/LockEditor.kt`): the picture big on top with Cancel / Done, tabs Looks · Layout · Dots · Words · Colors below, each choice drawn as what it gives (layout thumbnails, dot patches, "12" in each font, colour swatches); Pro choices can be tried and Done asks for Pro. Settings → Lock screen keeps only the preview, the on switch and "Edit look". `LockWallpaper.Style`; Classic is free, everything else Pro and falls back to the nearest free look without Pro (`LockStyleTest`). The paywall (rebuilt 2026-10-20, `billing/Paywall.kt`): a black carousel up top (five slides, turns every 3 s, pauses while dragged, swipeable; lock screen first), then every feature as a row with its small live picture that fades in as it scrolls into view, then a Free vs Pro table; the Yearly/Lifetime switch and the button stay pinned at the bottom and the button names the plan and price ("Get Pro for life · $14.99"). Settings shows Pro too: a dark "Get HabitDots Pro" card at the top while not Pro, a plain "HabitDots Pro · Lifetime" row once owned and a `ProBadge` on Pro rows (solid with a sparkle while locked, outlined once owned): Evening check-in, Sync, Lock screen → Edit look. Earlier the paywall opened with a wide "Lock screen looks" tile: three framed phones with a clock, drawn by the wallpaper code from a made-up year (`LockWallpaper.sample`), stepping through the eight looks. Buying or losing Pro redraws the lock screen (HabitApp collects `Pro.active`). Free/Pro verified on the S22 (2026-10-20): without Pro the page and wallpaper fall back to Classic, Pro looks show PRO and Done opens the paywall, a free look saves without it; with Pro, Calendar saves and draws; Pro lapsing redraws Classic, coming back redraws Calendar. Classic, Calendar and Ring also checked on the real lock screen, all eight in the in-app preview. Variants: https://claude.ai/artifact/MGQuMVjW1orD48gwWBQjNe Idea from the Easlo research: https://claude.ai/artifact/JF6D5P2ErYrgWWh5kVWj7C · mockups https://claude.ai/artifact/Rc9UL2v6YQLQX2gcG2vJwX
- **Widget settings in tabs (Android, 2026-10-20)**: the widget stays big on its wallpaper up top (tap to switch light/dark) with Cancel / Save; tabs below — Habit · Layout · Look · Dots, Rows · Look · Dots, or Show · Look — each choice drawn as what it gives. The selected chip has a ring with a gap so it shows on dark wallpapers.
- **Plain Inbox widget (Android, 2026-10-20)**: Show → Plain. No card, no checks: open tasks in large type right on the wallpaper, today's done ones stay struck through (`TaskDao.observeDoneSince`); a tap on a line completes it. Text tone follows the wallpaper hint or Text → Dark/Light (Samsung's hint describes the whole wallpaper, so a widget on its light half may need Dark). Not on iOS yet.
- **Inbox history (Android, 2026-10-20)**: a "Done · N" section at the bottom of the Inbox (collapsible), grouped by day (Today, Yesterday, dates), newest first, 30 at a time — the next page loads when its end scrolls into view (`TaskDao.observeDone(limit)`). The filled check takes a task back to the Inbox (`Tasks.reopen`). One-off tasks only. iOS: not yet.
- **Inbox widget options (Android, 2026-10-20)**: Show tab → "Done today: Show, struck through / Hide" (default Show for Plain, Hide for List; List shows them in the room left) and, for Plain, "Add button: Top / Bottom / Off" (a quiet + above the words, or a "+ New task" line; both open quick add).
- **Task priority removed (2026-10-20)**: no P1–P4 chip, flag, "p1" quick-add tag or priority sort, on either platform (the Inbox is: a task comes in, gets done, gone). The `priority` column stays in the shared schema and sync, unused.
- **Inbox widget** shows one-off tasks only: repeating tasks never appear (the Inbox is for things done once). "Show: Inbox" lists every open one-off task; "Show: Today" only those due today or overdue. iOS gained the same Show option (`InboxShowOption` in `Intents.swift`).

## Final QA pass, day 1 (2026-10-20, S22, debug build `app.habitdots.preview`)

Plan: https://claude.ai/artifact/SbgVmc2H2TjFjFe9qMz24w. Driven by `qa/ui.py` (new `tapx` = exact-text tap); the lock screen was checked through the `drawn` stamp in `shared_prefs/lock_wallpaper.xml`, since the phone's pattern lock stayed on and lock-screen screenshots were only possible at the start.

**Passed**: A1-A5 onboarding (own habit "Gym", 5th chip refused silently, no Pro anywhere, first dot saved, 21:00 reminders armed, permission asked); C1-C9 app -> widgets -> lock screen (check, uncheck, counter 1/3 -> 2/3 -> 3/3 -> clear, Complete yesterday from the card menu, rest day drawn as a dash, new habit, archive -> widget "Habit not found" -> unarchive, delete -> Recently deleted "30 days left" -> restore with its history, also with the app force-stopped); D1-D7 widgets -> app (checklist and single-habit checks, counter steps, name opens detail, "+N more" opens Habits, notification Done); E6 habit reminder at 21:00 only for the open habit; E7 evening check-in at 21:00 naming the open habit; F1 5th habit -> paywall; G1/G3/G4 Inbox add (date, repeat, no date), done -> Undo, Done - N history by day, reopen; H1-H5 Inbox widget List and Plain (repeating tasks never shown, quick add from the widget without opening the app, tap a plain line -> struck through, reopen in app -> widget updates); K1 midnight with the app open (cards reset, widgets 0/N, streaks kept, lock stamp next day); K2 midnight with the process killed (alarm fires, widgets and lock screen update); K3 +1 month (streaks lost), K4 back 3 days (no crash), clock restored (lock screen redrawn for the real day); M1 app Dark theme leaves widgets on their own setting; B1 the three card styles with 50 habits and long/RTL/emoji names; P4 font scale 1.3.

**Fixed on the way**: the lock screen now counts a day a habit was filled in for later (Complete yesterday) even if the habit was created after that day; the card-style picker's name row picks too (only the slab did).

**Notes, not bugs**: Force stop in Settings drops the midnight alarm until the next launch (Android's rule; swiping the app away does not). Samsung's "Fingerprint doesn't match" text sits on the lock-screen label line for a second. Plain Inbox widget with Text -> Auto drew white on the light half of a dark wallpaper (Dark fixes it; documented). At font scale 1.3 the Settings "Evening check-in" value truncates. Overdue tasks in the Inbox are red (`Overdue` in TodayScreen), the only colour left in the app: decide. Debug-build numbers with D2 (50 habits, 11 639 entries, 200 tasks): cold start 1.2 s, 21% janky frames, 284 MB PSS; release numbers from 2026-10-19 were 100-260 ms, 2%, 143 MB (the release install was skipped this time at the user's request).

**Not yet run**: J2 the five remaining lock-screen looks on the real lock screen (phone must be unlocked each time), I4 every look x layout on the home screen, K5-K7 (time zone, DST, reboot), L3-L5 (Test Store and Play purchases), N sync on two devices, O backup (verified 2026-10-19, code unchanged since), P1 release-build numbers, Q upgrade over Play 1.0, S iOS parity.

## QA on 2026-10-19 (Samsung S22 + iPhone 17 Pro simulator)

Every flow was driven by script with screenshots: onboarding, home, detail, Inbox, Settings, widgets, backup/CSV, trash, time travel (midnight, +10 days, +1 month, +1 year, clock back), 40 habits with long/RTL/emoji names, 200 tasks, dark mode, large text. Plan: https://claude.ai/artifact/Thdxs8jsXEhLq3pD85CmkU

Fixed on both platforms: "Complete yesterday" only added one to a counter; a tap on a done counter raised it invisibly past the target (now clears like a check); restoring from Recently deleted skipped the free limit; "Don't miss today!" stayed after the streak was gone; an auto-backup date left in the future stopped automatic copies; old dates now show their year; share cards carry "HabitDots". Android only: weekday chips wrapped "Mo"/"We"; widgets showed yesterday for up to an hour after midnight without exact-alarm access (now a 10-minute window); the checklist widget shows "+N more"; heatmap month labels no longer run into the dots at large text. iOS only: a card stayed faded after its long-press menu (onDrag ran with no drop).

Release-build performance (Android, 40 habits, a year of history): cold start 100–260 ms, 2% janky frames while scrolling, 143 MB.

## Store and payout facts

- **Google Play**: payouts approved to the Uzum Bank USD account (2026-10-19). Products `pro_yearly` (base plan `yearly`, 7-day trial) and `pro_lifetime` exist. The 15% service fee needs enrolling.
- **App Store**: IAP via StoreKit, through RevenueCat; 15% after enrolling in the Small Business Program. Uzbekistan is a storefront; pay the $99 with an international card. For payouts try Uzum Bank USD first under Agreements → Banking, else Payoneer/Wise. Fill W-8BEN.
- **Play closed testing** started 2026-10-16 (opt-in https://play.google.com/apps/testing/app.habitdots). **Apply for production on or after 2026-10-30.** 1.0.1 (versionCode 3, Google sign-in fix) was never uploaded: ship everything since in the production build with a new versionCode. The data-safety form must declare crash logs (Crashlytics).

## Moving to another Mac

These are not in git and must be copied by hand: `habit/app/google-services.json`, `habit-tracker-ios/HabitDots/GoogleService-Info.plist`, and the Android upload keystore in `~/.config/habitdots/` (with its passwords). Without the keystore no Play update can be signed. Claude's memory files live on this Mac only (`~/.claude/projects/-Users-furqat-apps-habit/memory/`); everything important from them is in this file.

## Next steps, in order

**Store setup (by hand, before release)**
0. **Next session: license-tester purchase on a Play build** (RevenueCat Play credentials and RTDN are done, see above). Blockers found 2026-10-19 on this Mac: the upload keystore folder `~/.config/habitdots/` (keystore.properties + .jks, plus play.json if it exists) is missing here — copy it from the other Mac by AirDrop/USB, not a cloud drive; and a real phone (S22, USB debugging) is needed, since the emulator has no Google account. Then: bump `versionCode` to 4, build the release `.aab`, upload to the internal track as a draft (`./gradlew publishBundle` once play.json is there, else by hand); add the tester Google account under Play Console → Settings → License testing and to the internal testers list; install from the internal test link; buy Yearly and Lifetime with Play's test card; check in RevenueCat that the purchase, the `pro` entitlement and an RTDN event arrive. After that: one Google account on both phones getting Pro from one purchase. If the keystore is lost, Play App Signing allows an upload-key reset (takes 1–2 days).
1. Play Console: enrolled in the 15% service fee (2026-10-19); prices per country are entered and saved (2026-10-19, table under "Prices" below); check `pro_yearly` (base plan `yearly`, 7-day free trial offer for new customers) and `pro_lifetime`; store listing text for the new Pro (unlimited habits, evening check-in, home screen looks, sync); data-safety form declares crash logs (Crashlytics).
2. On or after **2026-10-30**: Android production release with a new `versionCode` (1.0.1 / versionCode 3 was never uploaded).
3. Apple: developer account ($99, international card), Small Business Program (15%), Agreements → Banking (Uzum Bank USD, else Payoneer/Wise), W-8BEN, the same per-country prices as Play (table under "Prices"; nearest Apple tier); then `DEVELOPMENT_TEAM` in `project.yml` → TestFlight. On a signed build check what the simulator can't: real widgets in every look, the Inbox widget's Show option, a check from a widget refreshing the app, Liquid Glass.
4. Calendar: **2027-01-31** raise Lifetime from the launch $14.99 to $19.99 (the app reads prices from the store; no code change).

**Prices — what is in Play Console (entered and saved 2026-10-19).** Basis: World Bank 2024 price levels, Spotify's per-country ladder, HabitKit's and Habitify's real Play prices; FX of 2026-10-19. How it was done: "Set prices" from the US base ($7.99 / $14.99) lets Play convert, and Play's conversion already adds VAT where the shown price is tax-inclusive (EU, UK, Nordics, AU, JP, …) — those 100%-tier rows were kept as Play made them (so €8.49, not €7.99). Every other row below was then typed by hand (Monetize → Products → Subscriptions → `pro_yearly` → base plan `yearly`; One-time products → `pro_lifetime` → purchase option `buy`). Countries not listed keep Play's conversion. Russia/Belarus: Play billing is off. Kyrgyzstan/Tajikistan: Play has no subscriptions there, only the one-time product (priced in USD).

The same numbers go into App Store Connect when the Apple account exists: Apple's prices are tax-inclusive on every storefront and come in fixed tiers, so pick the nearest tier to each row (start from the US price, then override the discounted countries by hand; Apple's automatic equalisation does no purchasing-power cut either).

| Country | Cur. | % of US | Yearly (7-day trial) | Lifetime launch (now) | Lifetime from 2027-02 (planned) |
|---|---|---|---|---|---|
| United States | USD | 100 | 7.99 | 14.99 | 19.99 |
| Canada | CAD | 100 | 10.99 | 20.99 | 27.99 |
| United Kingdom | GBP | 100 | 6.99 | 13.49 | 17.99 |
| Eurozone | EUR | 100 | 8.49 (FI, GR, IE, PT 8.99) | 15.99 (FI, GR 16.99) | 20.99 (21.99) |
| Switzerland | CHF | 100 | 6.60 | 12.00 | 16.00 |
| Sweden | SEK | 100 | 99 | 185 | 245 |
| Norway | NOK | 100 | 95 | 175 | 235 |
| Denmark | DKK | 100 | 65 | 125 | 165 |
| Australia | AUD | 100 | 11.99 | 21.99 | 28.99 |
| New Zealand | NZD | 100 | 15.99 | 29.99 | 39.99 |
| Japan | JPY | 100 | 1,390 | 2,620 | 3,500 |
| South Korea | KRW | 90 | 9,900 | 19,900 | 24,900 |
| Singapore | SGD | 100 | 10.99 | 20.98 | 27.98 |
| Hong Kong | HKD | 100 | 60.90 | 118 | 158 |
| Taiwan | TWD | 70 | 190 | 360 | 450 |
| Israel | ILS | 100 | 24.90 | 46.90 | 62.90 |
| UAE | AED | 100 | 30.99 | 57.99 | 77.99 |
| Saudi Arabia | SAR | 100 | 33.99 | 64.99 | 84.99 |
| Qatar | QAR | 100 | 29 | 55 | 73 |
| Kuwait | USD | 100 | 7.99 | 14.99 | 19.99 |
| Poland | PLN | 60 | 22.99 | 42.99 | 56.99 |
| Czechia | CZK | 60 | 129 | 239 | 319 |
| Hungary | HUF | 60 | 1,990 | 3,690 | 4,890 |
| Romania | RON | 50 | 22.99 | 42.99 | 56.99 |
| Brazil | BRL | 45 | 17.90 | 34.90 | 45.90 |
| Mexico | MXN | 55 | 95 | 179 | 239 |
| Argentina | ARS | 35 | 3,999 | 7,999 | 10,999 |
| Chile | CLP | 45 | 4,200 | 7,900 | 10,500 |
| Colombia | COP | 40 | 9,900 | 18,900 | 24,900 |
| South Africa | ZAR | 45 | 69.99 | 129.99 | 169.99 |
| Türkiye | TRY | 35 | 169.99 | 309.99 | 409.99 |
| Kazakhstan | KZT | 40 | 1,690 | 3,190 | 4,290 |
| Ukraine | UAH | 35 | 149.99 | 279.99 | 369.99 |
| Malaysia | MYR | 45 | 15.90 | 29.90 | 39.90 |
| Thailand | THB | 40 | 109 | 219 | 289 |
| India | INR | 30 | 269 | 499 | 649 |
| Indonesia | IDR | 30 | 45,000 | 79,000 | 105,000 |
| Philippines | PHP | 35 | 199 | 369 | 489 |
| Vietnam | VND | 30 | 62,000 | 115,000 | 155,000 |
| Egypt | EGP | 25 | 119.99 | 229.99 | 299.99 |
| Pakistan | PKR | 25 | 550 | 1,050 | 1,400 |
| Bangladesh | BDT | 25 | 275 | 520 | 690 |
| Uzbekistan | UZS | 25 | 24,900 | 46,900 | 59,900 |
| Kyrgyzstan | USD | 25 | — (no Play subscriptions) | 3.99 | 4.99 |
| Tajikistan | USD | 25 | — (no Play subscriptions) | 3.99 | 4.99 |
| Nigeria | NGN | 20 | 2,300 | 4,300 | 5,700 |

Yearly : lifetime is ≈1 : 1.9 at launch and ≈1 : 2.5 after, so the paywall's "pays off in N years" line stays true. Review once a year: TRY, ARS, EGP, NGN and PKR lose value fast.

**Code, next phase**
5. One "Looks" gallery: card styles and widget looks chosen in one visual place, not a settings list (iOS has no widget-look picker in the app at all).
6. Widget looks wave 2: Pixel, Typewriter, Negative, Serif (backlog: Graph, Frame, Hatched, Ledger). Black, white and grey only.
7. Lock screen widgets; sections (Morning/Evening); a "2026 in dots" year share card before the new year; iOS 27 extra-large "Year in dots" widget.
8. Check by hand: drag-to-reorder on both phones.

**Known issues**
- iOS `HabitDotsTests/StoreTests` now checks only the Pro gates (purchases go through RevenueCat and are checked by hand); `androidTrashSnapshotReads` in HabitKit is flaky.
- DotGothic16 font is 2 MB (full CJK set); subset it.
- The note field is a single line; CSV export leaves out counter values and rest days; unsaved edits are lost if Android kills the app; a database with an invalid time crashes on launch (only via a hand-made file).
- On the test phone the preview app (`app.habitdots.preview`) was reset; Pretend Pro is off.

## Artifacts (private, claude.ai)

- **Final A–Z QA plan (2026-10-20, before release; checkboxes persist in the browser): https://claude.ai/artifact/SbgVmc2H2TjFjFe9qMz24w**
- QA plan 2026-10-19: https://claude.ai/artifact/Thdxs8jsXEhLq3pD85CmkU
- QA report with screenshots (2026-10-17): https://claude.ai/artifact/2vvVdYZj6sTdJKdHi1z7Ur
- Habit card view variants: https://claude.ai/artifact/1V59pt4oT3oKQ5vgp5cTkr
- Habits header variants (card-style button placement, still open): https://claude.ai/artifact/Y8zpnzyVrRnkCcCuDdE9b2
