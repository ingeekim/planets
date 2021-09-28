import Fluent
import Vapor
import Redis

func routes(_ app: Application) throws {
    app.get { req in
        return "It works!"
    }

    app.get("hello") { req -> String in
        return "Hello, world!"
    }
    
    app.get("ping") { req in
        return req.redis.ping()
    }

    try app.register(collection: PlanetController())
}
