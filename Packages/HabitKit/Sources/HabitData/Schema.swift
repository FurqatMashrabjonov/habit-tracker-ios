import Foundation
import GRDB

/*
 * The Android app's Room schema, version 8, statement for statement (copied from
 * habit-tracker/app/schemas/.../8.json). Room validates a database it opens against this shape and
 * its identity hash, so an iPhone backup restores on Android too; `IF NOT EXISTS` lets an Android
 * backup open here.
 */
enum Schema {
    static let version: Int32 = 8
    static let roomIdentityHash = "0cd8083b07b88931883b3479c03e68c3"

    static let statements = [
        "CREATE TABLE IF NOT EXISTS `tracker` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `icon` TEXT NOT NULL, `color` INTEGER NOT NULL, `type` TEXT NOT NULL, `dailyTarget` INTEGER NOT NULL, `unit` TEXT NOT NULL, `direction` TEXT NOT NULL, `sortOrder` INTEGER NOT NULL, `archived` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, `cue` TEXT, `identity` TEXT, `reminder` INTEGER, `schedule` TEXT, `uuid` TEXT NOT NULL DEFAULT '', `updatedAt` INTEGER NOT NULL DEFAULT 1)",
        "CREATE UNIQUE INDEX IF NOT EXISTS `index_tracker_uuid` ON `tracker` (`uuid`)",
        "CREATE TABLE IF NOT EXISTS `entry` (`trackerId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `value` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(`trackerId`, `date`), FOREIGN KEY(`trackerId`) REFERENCES `tracker`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
        "CREATE TABLE IF NOT EXISTS `task` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `title` TEXT NOT NULL, `dueDate` INTEGER, `dueTime` INTEGER, `repeat` TEXT, `priority` INTEGER NOT NULL, `done` INTEGER NOT NULL, `completedAt` INTEGER, `createdAt` INTEGER NOT NULL)",
        "CREATE TABLE IF NOT EXISTS `note` (`trackerId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `text` TEXT NOT NULL, `updatedAt` INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(`trackerId`, `date`), FOREIGN KEY(`trackerId`) REFERENCES `tracker`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
        "CREATE TABLE IF NOT EXISTS `tombstone` (`key` TEXT NOT NULL, `deletedAt` INTEGER NOT NULL, PRIMARY KEY(`key`))",
        "CREATE TABLE IF NOT EXISTS `trash` (`uuid` TEXT NOT NULL, `name` TEXT NOT NULL, `deletedAt` INTEGER NOT NULL, `data` TEXT NOT NULL, PRIMARY KEY(`uuid`))",
        "CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)",
        "INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, '\(roomIdentityHash)')",
    ]

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        // ponytail: one step. Every Android build in the wild is already at version 8; older backups
        // (versions 1-7) are refused at import instead of migrated here.
        m.registerMigration("v8") { db in
            for sql in statements { try db.execute(sql: sql) }
            try db.execute(sql: "PRAGMA user_version = \(version)")
        }
        return m
    }

    /// True for a SQLite file carrying this schema (an Android or iPhone backup).
    static func accepts(_ db: Database) throws -> Bool {
        try Int32.fetchOne(db, sql: "PRAGMA user_version") == version && db.tableExists("tracker") && db.tableExists("trash")
    }
}
