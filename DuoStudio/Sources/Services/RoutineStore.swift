import Foundation
import PoseCore

/// Where imported dance routines live: `Application Support/Routines/` holds each reference video
/// (`<uuid>.<ext>`) plus `routines.json`, the skeleton timelines and metadata. Imported reference
/// videos and this index persist until the user deletes the routine — recordings never land here.
///
/// Deliberately never reads file timestamps (creation/modification dates), so `PrivacyInfo
/// .xcprivacy` needs no file-timestamp API reason.
enum RoutineStore {
    private static let indexFileName = "routines.json"

    /// The Routines directory, created on demand.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Routines", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Every saved routine; empty on any failure (missing or unreadable index).
    static func load() -> [DanceRoutine] {
        let url = directory.appendingPathComponent(indexFileName)
        guard
            let data = try? Data(contentsOf: url),
            let routines = try? JSONDecoder().decode([DanceRoutine].self, from: data)
        else { return [] }
        return routines
    }

    static func save(_ routines: [DanceRoutine]) {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        try? data.write(to: directory.appendingPathComponent(indexFileName), options: .atomic)
    }

    static func mediaURL(for routine: DanceRoutine) -> URL {
        directory.appendingPathComponent(routine.mediaFileName)
    }

    /// Removes the routine's video file. The caller updates and re-saves the index.
    static func delete(_ routine: DanceRoutine) {
        try? FileManager.default.removeItem(at: mediaURL(for: routine))
    }
}
