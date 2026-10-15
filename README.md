# HabitDots for iPhone

Native SwiftUI version of [HabitDots](https://github.com/FurqatMashrabjonov/habit-tracker): a calm,
black and white habit tracker. Same design, animations, widgets and Pro as the Android app.

- `Packages/HabitKit`: shared code for the app and the widget.
  - `HabitDomain`: days, schedules, "never miss twice" streaks, task repeats, CSV. Same tests as Android.
  - `HabitData`: SQLite through GRDB with the Android app's exact Room schema (v8), so a backup
    file moves between an Android phone and an iPhone.
  - `HabitDesign`: colors, Inter type, radii, and the drawings (check, day dots, confetti, ring).
- `HabitDots/`: the app. `HabitDotsWidget/`: home screen widgets.
- `project.yml`: XcodeGen spec; the `.xcodeproj` is generated, not committed.

```sh
brew install xcodegen
xcodegen generate && open HabitDots.xcodeproj
cd Packages/HabitKit && swift test   # runs on a Mac, no simulator needed
```
