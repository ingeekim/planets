import Fluent
import Vapor
import Redis

struct PlanetController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let planetRoutes = routes.grouped("planets")
        planetRoutes.get(use: indexHandler)
        planetRoutes.post(use: createHandler)
        planetRoutes.group(":planetID") { planet in
            planet.delete(use: deleteHandler)
        }
        planetRoutes.get(":planetID", use: findHandler)
    }

    func indexHandler(req: Request) throws -> EventLoopFuture<[Planet]> {
        return Planet.query(on: req.db).all()
    }

    func createHandler(req: Request) throws -> EventLoopFuture<Planet> {
        let planet = try req.content.decode(Planet.self)
        return planet.save(on: req.db).map { planet }
    }

    func deleteHandler(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        return Planet.find(req.parameters.get("planetID"), on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap { $0.delete(on: req.db) }
            .transform(to: .ok)
    }
    
    func findHandler(req: Request) throws -> EventLoopFuture<Planet> {
        guard let searchID: UUID = req.parameters.get("planetID") else {
            req.logger.error("planetID has not been specified.")
            throw Abort(.badRequest)
        }
        let planetKey = RedisKey(String(searchID))
        
        let redisPlanet: EventLoopFuture<Planet?> = req.redis.get(planetKey, asJSON: Planet.self)
        
        let cachedPlanet: EventLoopFuture<Planet> = redisPlanet.flatMapThrowing {
            (cached: Planet?) throws -> (Planet) in
            guard let planet = cached else {
                req.logger.info("cache missed.")
                return Planet(id: searchID, name: "Failure")
            }
            req.logger.info("cache hit.")
            return planet
        }
        
        return cachedPlanet.flatMap { (cached: Planet) -> (EventLoopFuture<Planet>) in
            if cached.name != "Failure" {
                return cachedPlanet
            }
            return Planet.find(searchID, on: req.db).flatMapThrowing { (found: Planet?) -> (Planet) in
                guard let planet = found else {
                    req.logger.error("database miss.")
                    throw Abort(.notFound)
                }
                req.redis.set(planetKey, toJSON: planet).whenComplete { result in
                    switch result {
                    case .success:
                        req.logger.info("\(planet) cached")
                        expireTheKey(planetKey, redis: req.redis)
                    case .failure(let error):
                        req.logger.info("Cache error: \(error)")
                    }
                }
                return planet
            }
        }
    }
    
    private func expireTheKey(_ key: RedisKey, redis: Vapor.Request.Redis) {
        // This expires the key after 30 sec for demonstration purposes
        let expireDuration = TimeAmount.seconds(30)
        let _ = redis.expire(key, after: expireDuration)
    }
}
