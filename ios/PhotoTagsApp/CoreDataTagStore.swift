import Foundation
import CoreData
import PhotoTagsCore

struct AssetTagRecord: Sendable {
    let id: String
    let tags: [String]
    let annotatedAt: Date?
}

@objc(AssetEntity)
final class AssetEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var tagsRaw: String
    @NSManaged var annotatedAt: Date?
}

extension AssetEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AssetEntity> {
        NSFetchRequest<AssetEntity>(entityName: "AssetEntity")
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRaw = TaggedPhoto.normalizeTags(newValue).joined(separator: ",")
        }
    }
}

final class CoreDataTagStore {
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "PhotoTagsModel", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("CoreData persistent store load failed: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func allRecords() throws -> [AssetTagRecord] {
        let req = AssetEntity.fetchRequest()
        let rows = try container.viewContext.fetch(req)
        return rows.map { AssetTagRecord(id: $0.id, tags: $0.tags, annotatedAt: $0.annotatedAt) }
    }

    func tags(for assetID: String) throws -> [String] {
        let req = AssetEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", assetID)
        req.fetchLimit = 1
        guard let row = try container.viewContext.fetch(req).first else { return [] }
        return row.tags
    }

    func upsert(assetID: String, tags: [String], annotatedAt: Date = .now) throws {
        let normalized = TaggedPhoto.normalizeTags(tags)
        guard !normalized.isEmpty else { return }

        let context = container.viewContext
        let req = AssetEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", assetID)
        req.fetchLimit = 1

        let entity = try context.fetch(req).first ?? AssetEntity(context: context)
        entity.id = assetID
        entity.tags = Array(Set(entity.tags + normalized))
        entity.annotatedAt = annotatedAt

        try context.save()
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "AssetEntity"
        entity.managedObjectClassName = NSStringFromClass(AssetEntity.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .stringAttributeType
        id.isOptional = false
        id.isIndexed = true

        let tagsRaw = NSAttributeDescription()
        tagsRaw.name = "tagsRaw"
        tagsRaw.attributeType = .stringAttributeType
        tagsRaw.isOptional = false
        tagsRaw.defaultValue = ""

        let annotatedAt = NSAttributeDescription()
        annotatedAt.name = "annotatedAt"
        annotatedAt.attributeType = .dateAttributeType
        annotatedAt.isOptional = true

        entity.properties = [id, tagsRaw, annotatedAt]
        model.entities = [entity]
        return model
    }
}
