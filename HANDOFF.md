# HabitDots handoff — 2026-10-18

Where both apps stand, what was decided, and what comes next. Same file in both repos.

## Repos and environment

| | Android | iOS |
|---|---|---|
| Repo | `github.com/FurqatMashrabjonov/habit-tracker` | `github.com/FurqatMashrabjonov/habit-tracker-ios` |
| Local path (old laptop) | `~/apps/habit-tracker` | `~/apps/habit-tracker-ios` |
| Stack | Kotlin, Compose, Room v8 | SwiftUI, GRDB (same schema), XcodeGen (`project.yml`) |
| Build | `./gradlew :app:installDebug` | `xcodegen generate` then `xcodebuild -project HabitDots.xcodeproj -scheme HabitDots -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` |
| Tests | `./gradlew :app:testDebugUnitTest` | `cd Packages/HabitKit && swift test` |
| Latest commit | `9a14b52` | `2055ccc` |

- **Firebase project** `habitdots-app`: Auth (Google provider only), Firestore `users/{uid}/habits`, `months`; Crashlytics (crash logs only, release builds). No Analytics.
- **Gitignored secrets** you must recreate on the new machine: `app/google-services.json` (Android) and `HabitDots/GoogleService-Info.plist` (iOS). Get them from the Firebase console (project settings → your apps) or via the Firebase MCP tool `firebase_get_sdk_config`. Android does not compile without it (`default_web_client_id`).
- **Android upload keystore** is in `~/.config/habitdots/` on the old laptop — copy it over, it is not in git.
- **iOS signing**: `DEVELOPMENT_TEAM` is not set in `project.yml`; there is no Apple Developer account yet.
- **QA harness** (`~/apps/habit-tracker-qa/2026-10-17/`, not in git): `adbui.py` (adb) and `idbui.py` (idb) drive emulator/simulator: dump/tap/xy/swipe/text/shot/rec/db. iOS debug launch args: `-demo`, `-paywall`, `-pretendPro YES|NO`, `-open <id>`, `-bottom`, `-restore <path>`, `-settings`, `-inbox`, `-add`. Android debug: Settings → "Pretend Pro".
- Shared Room/GRDB schema: `tracker`, `entry` (value −1 = rest day), `task` (priority 1–4, 4 = none), `note`, `tombstone`, `trash`. Backups restore across platforms (verified both ways).

## What shipped this week (both platforms unless noted)

- Crashlytics; free habit limit 4 (`Pro.FREE_HABITS` / `Store.freeHabits`); momentum helper in domain.
- Priority flags are ink shades (monochrome), `p1`–`p4` parsed from a task title.
- Habits ↔ Inbox is a connected pager like Telegram tabs (swipe or the bottom pill).
- **Card style picker**: one button beside the "Habits" title opens a sheet that previews every style with the user's own first habit. Three styles, upgraded: Dot wall (month labels, today ringed), Last 7 days (weekday letters, "N/7 this week"), Name only (micro week strip). Pref key `cards`; styles other than Dot wall are Pro-gated today (`CardStyle.pro`).
- Sign-in is Google only (Apple sign-in removed from iOS; Firebase Auth has only the Google provider).
- Archive/unarchive from Settings and from a habit's page; paywall from the Settings sheet works.
- **Statistics screen removed** (both). The habit's own page (heatmap, streak, best, notes) is the statistics. Header is now: settings (left), add (right), card-style button beside the title. Paywall tile "Statistics" became "Card styles".
- Reverted and kept only in git history (if ever wanted back): three extra card styles Rings/Chain/Month (`8e1a1dd` iOS, `87fd5f1` Android) and the Statistics "All" overview with perfect days, year in dots, insights (`4c1d069` iOS, `d401fc3` Android).

## Decisions (not implemented yet)

1. **Pro = unlimited habits + sync. Everything else free** — card styles, widget looks, reminders, backup/restore. Never gate export/import (user's own data). Keep the paywall promise "Tracking, widgets, reminders and your data stay free, with up to 4 habits."
2. **Pricing**: Lifetime **$14.99** as the hero, launch price **$9.99** for the first 2–3 months (show the struck $14.99); Yearly **$5.99** with the 7-day trial. Turn on regional (storefront) pricing in both stores. Not lower than ~$10 lifetime: sync has a recurring Firestore cost per user.
3. **iOS first for revenue, Android for reach.** Promote on X/indie community, r/iOSapps, Product Hunt, home-screen-setup content (widgets).
4. Statistics stays removed. Card-style button placement is still open — see the header variants artifact below; candidate: variant 2 ("Habits ⌄", the title opens the picker, no extra button).
5. Free habit limit stays 4; revisit after seeing purchase numbers (there is no analytics, only store purchase reports).

## Store and payout facts (checked 2026-10-18)

- **Google Play**: Uzbekistan supports developer *and* merchant registration, payouts in USD (official list). Pro products `pro_yearly` (base plan `yearly`, 7-day trial) and `pro_lifetime` exist and were tested with a license tester.
- **App Store**: in-app purchases go through Apple's IAP/StoreKit (not Apple Pay). Apple keeps 30%, or 15% after enrolling in the Small Business Program. Uzbekistan is an App Store storefront. Enrollment from Uzbekistan works but pay the $99 with an international Visa/Mastercard (a forum report shows a local card stalling for a month). Apple publishes no list of payout banks: after enrolling, search for your bank under Agreements → Banking; if it is not found, use a Payoneer or Wise USD receiving account. Fill W-8BEN.
- **Play closed testing** started 2026-10-16 (opt-in https://play.google.com/apps/testing/app.habitdots). **Do not deploy anything before 2026-10-30**; apply for production on or after that date. 1.0.1 (versionCode 3, Google sign-in fix) is not uploaded yet — fold it into the production build with a new versionCode. The Play data-safety form must now declare crash logs (Crashlytics).

## Next steps, in order

1. **Implement the Pro plan** (both platforms): remove `CardStyle.pro` gating and the lock/Pro labels in the picker (`TodayView.swift` CardStylePicker / `TodayScreen.kt` CardStylePicker, `ThemePref.cards`), remove the widget-look gate, cut the paywall to two tiles (Unlimited habits, Sync) and update its copy and "pays off" line (`Paywall.swift`, `billing/Paywall.kt`, `Store.swift`, `billing/Pro.kt`, strings). Real prices are set in Play Console / App Store Connect by hand.
2. Decide the card-style button placement (artifact) and apply it.
3. iOS: Apple Developer account → `DEVELOPMENT_TEAM` in `project.yml` → TestFlight. Release build uploads dSYMs to Crashlytics (script in `project.yml`, only when the plist exists).
4. Android, on/after 2026-10-30: production release with the sign-in fix, data-safety update, regional prices.
5. Smaller open notes from the QA run: widget rows (N-10), counter reset (N-4), rest day via widget (N-25), CSV export (N-8); exact-alarm help, a11y labels, licenses screen (see `TODO.md` in the Android repo).

## Artifacts (private, claude.ai)

- QA report with screenshots (2026-10-17): https://claude.ai/artifact/2vvVdYZj6sTdJKdHi1z7Ur
- Habit card view variants: https://claude.ai/artifact/1V59pt4oT3oKQ5vgp5cTkr
- Statistics page variants (now moot): https://claude.ai/artifact/BK81gnSJHP22V54vrLyy1b
- Habits header variants (card-style button placement): https://claude.ai/artifact/Y8zpnzyVrRnkCcCuDdE9b2
