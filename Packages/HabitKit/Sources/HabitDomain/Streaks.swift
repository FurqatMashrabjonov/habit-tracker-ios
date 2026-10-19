/*
 * Streaks follow "never miss twice" (Atomic Habits): a single missed day is forgiven, two misses
 * in a row break the streak. Streak length counts completed days only. Same rules as the Android app.
 */

/// value / target; may exceed 1.
public func progress(_ value: Int, target: Int) -> Double {
    target <= 0 ? 0 : Double(value) / Double(target)
}

/// Days streaks step over; see `Schedule.skip`. Default: none.
public typealias Skip = (Day) -> Bool

/// Today not done yet is not a miss: it's still in progress.
public func currentStreak(_ done: Set<Day>, today: Day, skip: Skip = { _ in false }) -> Int {
    guard let first = done.min() else { return 0 }
    var day = done.contains(today) ? today : today - 1
    var n = 0
    var misses = 0
    while misses < 2 && day >= first {
        if done.contains(day) { n += 1; misses = 0 } else if !skip(day) { misses += 1 }
        day = day - 1
    }
    return n
}

public func bestStreak(_ done: Set<Day>, skip: Skip = { _ in false }) -> Int {
    guard let first = done.min(), let last = done.max() else { return 0 }
    var best = 0
    var run = 0
    var misses = 0
    var day = first
    while day <= last {
        if done.contains(day) {
            run = misses >= 2 ? 1 : run + 1
            misses = 0
            best = max(best, run)
        } else if !skip(day) {
            misses += 1
        }
        day = day + 1
    }
    return best
}

/// The last due day was missed and today isn't done yet: one more miss breaks the streak.
public func mustNotMissToday(_ done: Set<Day>, today: Day, since: Day, skip: Skip = { _ in false }) -> Bool {
    if done.contains(today) || skip(today) { return false }
    var day = today - 1
    while day >= since && skip(day) { day = day - 1 }
    // Only while there is a streak to save: after two misses it's already gone.
    return day >= since && !done.contains(day) && currentStreak(done, today: today, skip: skip) > 0
}

/// Streak lengths that earn a badge.
public let milestones = [1, 7, 14, 30, 50, 100, 200, 365]
