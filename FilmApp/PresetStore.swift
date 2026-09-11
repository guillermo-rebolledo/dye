import Foundation
import SwiftData

/// Where **Presets** live, and what happens when that store cannot be opened.
///
/// `.modelContainer(for:)` calls `fatalError` when the container cannot be created,
/// which turns a corrupt store or a failed migration into an unrecoverable launch
/// crash: the user's only way back into the app is to delete it. A photo editor's
/// saved looks are not worth the app itself, so this opens the store explicitly and
/// falls back to an in-memory one. The app launches, the editor works, and the
/// Presets sheet says what happened instead of the app saying nothing at all.
enum PresetStore {

    /// What opening the store actually did, so the interface can be honest about it.
    enum Outcome: Equatable {
        /// The store on disk opened, and Presets saved before this launch are there.
        case onDisk
        /// The store on disk could not be opened. Presets work for this session only.
        case inMemory
    }

    /// The schema as it shipped in 1.0. A `VersionedSchema` exists from the first
    /// version precisely so the second one has somewhere to go: the migration that
    /// breaks is the one nobody planned, and by then the app is live.
    enum SchemaV1: VersionedSchema {
        static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
        static var models: [any PersistentModel.Type] { [Preset.self] }
    }

    /// Empty today, and that is the point — v2 adds its stage here rather than
    /// discovering at upgrade time that there is nowhere to put one.
    enum MigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }

    /// The container the app runs on, and what it cost to get it.
    ///
    /// Returns rather than throws: there is no caller above this that could do
    /// anything useful with a failure, and the whole point is that launch survives.
    static func open() -> (container: ModelContainer, outcome: Outcome) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: MigrationPlan.self,
                                               configurations: ModelConfiguration(schema: schema))
            return (container, .onDisk)
        } catch {
            do {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return (try ModelContainer(for: schema, configurations: configuration), .inMemory)
            } catch {
                // An in-memory container needs no disk, no permission and no migration.
                // If this fails, SwiftData itself is unusable and there is no app to run.
                fatalError("Presets cannot be stored even in memory: \(error)")
            }
        }
    }
}
