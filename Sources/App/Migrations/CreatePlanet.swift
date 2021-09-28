import Fluent

struct CreatePlanet: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("planet")
            .id()
            .field("name", .string)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("planet").delete()
    }
}
