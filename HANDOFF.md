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
- **Prices** (set by hand in the stores): Yearly **$7.99** with a 7-day trial (default choice), Lifetime **$19.99** as the hero, launch price **$14.99** until ~2027-01-31. No monthly. Regional prices by purchasing power: BR/TR/MX/KZ ~50%, IN/ID ~35%, UZ ~25–30% of the US price. Research and the full table: see the Pro research in the 2026-10-19 session.
- **Next Pro candidates** (not built): sections (Morning/Evening), a year wall with a "2026 in dots" share card before the new year, later a web version.

## Billing through RevenueCat (2026-10-19, both platforms)

Pro is one RevenueCat entitlement shared by both apps, so a purchase on either phone unlocks both once the user signs in with the same Google account.

- **Dashboard**: project **HabitDots** `proj0ae14c1e` (https://app.revenuecat.com/projects/0ae14c1e). Apps: Play `app.habitdots` (`app153e95cfcf`), App Store `app.habitdots` (`appbdc9ca5aec`), Test Store (`appc4b98ade81`). Entitlement `pro`. Products: Play `pro_yearly:yearly` and `pro_lifetime`; App Store and Test Store `pro_yearly` and `pro_lifetime` (Test Store prices $7.99 / $19.99). Offering `default` (current) with packages `$rc_annual` and `$rc_lifetime`.
- **Identity**: the RevenueCat app user ID is the Firebase uid. A Firebase auth-state listener calls `logIn(uid)` on sign-in and `logOut()` on sign-out or account deletion. Purchases made before signing in are anonymous and merge into the uid on the first sign-in.
- **Code**: same facades as before, only the internals changed. Android `billing/Pro.kt` (SDK `com.revenuecat.purchases:purchases` 10.28.1, Play Billing dependency removed). iOS `HabitDots/Store.swift` (SPM `purchases-ios-spm` 5.96.0 in `project.yml`). The paywall and every gate are untouched; `Shared.pro` still feeds the iOS widgets; "Pretend Pro" still works in debug.
- **Keys**: debug builds use the Test Store key (`test_…`), release builds the store keys (`goog_…`, `appl_…`). Test Store purchases show a "Test valid purchase" dialog and need no store account. Never ship a release built with the test key: the SDK crashes in production with it.
- **Verified 2026-10-19**: Test Store purchase of Lifetime on the Android emulator (anonymous user) and of Yearly on the iOS simulator (signed in, uid `038JVlA89ZaTo2jBaE9BIRza8Ga2`): both unlock Pro, and the dashboard shows the entitlement. **Not yet verified**: the same Google account on both phones getting Pro from one purchase (the emulator has no Google account). Check it on the S22 preview build signed into the account the simulator uses.
- **Still to connect (by hand)**: Play service-account JSON in RevenueCat (Google Cloud service account with Play Console financial and order permissions; can take up to ~36 h to work) plus Real-time developer notifications (Pub/Sub) so refunds show. App Store: In-App Purchase key (.p8) and App Store Server Notifications once the Apple account exists. Until the Play credentials are in, release builds cannot validate real purchases.
- Free under $2,500 monthly tracked revenue, then 1%. Money still goes straight from Google and Apple to the bank.

## Onboarding (upgraded 2026-10-19, both platforms)

Four steps on the existing animated flow: 1 the deck of cards, 2 pick habits (a "Your own" chip comes first and turns into a text field; typed habits join the picks), 3 **first dot**: "Did you read 20 pages today?" ("No sugar today?", "Gym today?" for "No ..." and typed habits); the box or "Done it today" saves a real entry so home opens at 1/N, 4 the widgets, then "Remind me at 08:00 / 21:00 / Never" (21:00 default) for every picked habit; notification permission asked on the last tap.

User's rules for onboarding: **never mention or show Pro** (no looks step, no free-limit text; the 4-habit limit holds silently under "Fewer is easier to keep."), **no colour or emoji** (the streak line uses the app's flame icon), **users can type their own habit**. "I already use HabitDots" goes straight to Google sign-in with no paywall: a returning Pro user's purchase comes back from the store and sync (Pro only, `Sync.kt`) brings the habits; a non-Pro user just lands in the app, and Settings → Sync says sync is paused.

## Other changes on 2026-10-19 (afternoon)

- **Settings → Appearance** shows only the app theme (System/Light/Dark). Card styles are on the home screen; widget light/dark is in each widget's settings (Android).
- **Card style button** moved next to the add button, a round header button like Settings whose icon is the style in use (wall / four squares / rows). The picker has no frames or checkboxes: each style's real card sits on its own grey slab (darker with an "In use" tag for the current one); one tap picks and closes.
- **Inbox widget** shows one-off tasks only: repeating tasks never appear (the Inbox is for things done once). "Show: Inbox" lists every open one-off task; "Show: Today" only those due today or overdue. iOS gained the same Show option (`InboxShowOption` in `Intents.swift`).

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
0. RevenueCat: upload the Play service-account JSON and turn on Real-time developer notifications (see "Billing through RevenueCat"). Do this first: the credentials can take a day and a half to start working. Then test a license-tester purchase on a Play build, and one Google account on both phones.
1. Play Console: enrol in the 15% service fee; set the prices and regional prices below; check `pro_yearly` (base plan `yearly`, 7-day free trial offer for new customers) and `pro_lifetime`; store listing text for the new Pro (unlimited habits, evening check-in, home screen looks, sync); data-safety form declares crash logs (Crashlytics).
2. On or after **2026-10-30**: Android production release with a new `versionCode` (1.0.1 / versionCode 3 was never uploaded).
3. Apple: developer account ($99, international card), Small Business Program (15%), Agreements → Banking (Uzum Bank USD, else Payoneer/Wise), W-8BEN, same prices and tiers; then `DEVELOPMENT_TEAM` in `project.yml` → TestFlight. On a signed build check what the simulator can't: real widgets in every look, the Inbox widget's Show option, a check from a widget refreshing the app, Liquid Glass.
4. Calendar: **2027-01-31** raise Lifetime from the launch $14.99 to $19.99 (the app reads prices from the store; no code change).

**Prices** (researched 2026-10-19: World Bank 2024 price levels, Spotify's 46-country ladder, HabitKit's and Habitify's real Play prices per country; FX of 2026-10-19). Enter by hand per country in Play Console (Monetize → Products → Subscriptions → `pro_yearly` → base plan `yearly`; One-time products → `pro_lifetime`); Play's own "convert" is exchange rate only, no purchasing-power cut. Prices are tax-inclusive where Play shows them so (EU, UK, TR, BR, IN, …): the EU/UK prices sit at the US sticker on purpose, the VAT comes out of them. Countries not listed: leave Play's conversion. Russia/Belarus: Play billing is off, nothing to set.

| Country | Cur. | % of US | Yearly | Lifetime launch | Lifetime from 2027-02 |
|---|---|---|---|---|---|
| United States | USD | 100 | 7.99 | 14.99 | 19.99 |
| Canada | CAD | 100 | 10.99 | 20.99 | 27.99 |
| United Kingdom | GBP | 100 | 6.99 | 12.99 | 17.99 |
| Eurozone (one price) | EUR | 100 | 7.99 | 14.99 | 19.99 |
| Switzerland | CHF | 100 | 7.00 | 13.00 | 17.00 |
| Sweden | SEK | 100 | 79 | 149 | 199 |
| Norway | NOK | 100 | 79 | 139 | 189 |
| Denmark | DKK | 100 | 55 | 99 | 135 |
| Australia | AUD | 100 | 11.99 | 21.99 | 28.99 |
| New Zealand | NZD | 100 | 13.99 | 26.99 | 34.99 |
| Japan | JPY | 100 | 1,200 | 2,300 | 3,000 |
| South Korea | KRW | 90 | 9,900 | 17,900 | 24,900 |
| Singapore | SGD | 100 | 10.98 | 19.98 | 25.98 |
| Hong Kong | HKD | 100 | 62 | 118 | 158 |
| Taiwan | TWD | 70 | 180 | 340 | 450 |
| Israel | ILS | 100 | 24.90 | 46.90 | 62.90 |
| UAE | AED | 100 | 28.99 | 54.99 | 72.99 |
| Saudi Arabia | SAR | 100 | 29.99 | 55.99 | 74.99 |
| Poland | PLN | 60 | 18.99 | 34.99 | 46.99 |
| Czechia | CZK | 60 | 99 | 199 | 259 |
| Hungary | HUF | 60 | 1,490 | 2,890 | 3,890 |
| Romania | RON | 50 | 18.99 | 35.99 | 46.99 |
| Brazil | BRL | 45 | 18.90 | 34.90 | 45.90 |
| Mexico | MXN | 55 | 79 | 149 | 199 |
| Argentina | ARS | 35 | 3,999 | 7,999 | 10,999 |
| Chile | CLP | 45 | 3,500 | 6,600 | 8,800 |
| Colombia | COP | 40 | 9,900 | 18,900 | 24,900 |
| South Africa | ZAR | 45 | 59.99 | 109.99 | 149.99 |
| Türkiye | TRY | 35 | 139.99 | 259.99 | 349.99 |
| Kazakhstan | KZT | 40 | 1,490 | 2,690 | 3,590 |
| Ukraine | UAH | 35 | 124.99 | 234.99 | 314.99 |
| Malaysia | MYR | 45 | 14.90 | 27.90 | 36.90 |
| Thailand | THB | 40 | 109 | 199 | 269 |
| India | INR | 30 | 229 | 429 | 579 |
| Indonesia | IDR | 30 | 42,000 | 79,000 | 109,000 |
| Philippines | PHP | 35 | 179 | 329 | 449 |
| Vietnam | VND | 30 | 59,000 | 115,000 | 155,000 |
| Egypt | EGP | 25 | 99.99 | 199.99 | 269.99 |
| Pakistan | PKR | 25 | 549 | 1,049 | 1,399 |
| Nigeria | NGN | 20 | 2,100 | 4,000 | 5,300 |
| Bangladesh | BDT | 25 | 249 | 459 | 619 |
| Uzbekistan | UZS | 25 | 24,900 | 46,900 | 59,900 |
| Kyrgyzstan | KGS | 25 | 169 | 329 | 439 |

Keep the yearly : lifetime ratio the same everywhere (≈1 : 1.9 at launch, 1 : 2.5 after), so the paywall's "pays off in N years" line stays true. Review once a year: TRY, ARS, EGP, NGN and PKR lose value fast.

**Code, next phase**
5. Priority placement: where the Inbox priority flag and ordering show on widgets and the home screen.
6. One "Looks" gallery: card styles and widget looks chosen in one visual place, not a settings list (iOS has no widget-look picker in the app at all).
7. Widget looks wave 2: Pixel, Typewriter, Negative, Serif (backlog: Graph, Frame, Hatched, Ledger). Black, white and grey only.
8. Lock screen widgets; sections (Morning/Evening); a "2026 in dots" year share card before the new year; iOS 27 extra-large "Year in dots" widget.
9. Check by hand: drag-to-reorder on both phones.

**Known issues**
- iOS `HabitDotsTests/StoreTests` now checks only the Pro gates (purchases go through RevenueCat and are checked by hand); `androidTrashSnapshotReads` in HabitKit is flaky.
- DotGothic16 font is 2 MB (full CJK set); subset it.
- The note field is a single line; CSV export leaves out counter values and rest days; unsaved edits are lost if Android kills the app; a database with an invalid time crashes on launch (only via a hand-made file).
- On the test phone the preview app (`app.habitdots.preview`) was reset; Pretend Pro is off.

## Artifacts (private, claude.ai)

- QA plan 2026-10-19: https://claude.ai/artifact/Thdxs8jsXEhLq3pD85CmkU
- QA report with screenshots (2026-10-17): https://claude.ai/artifact/2vvVdYZj6sTdJKdHi1z7Ur
- Habit card view variants: https://claude.ai/artifact/1V59pt4oT3oKQ5vgp5cTkr
- Habits header variants (card-style button placement, still open): https://claude.ai/artifact/Y8zpnzyVrRnkCcCuDdE9b2
