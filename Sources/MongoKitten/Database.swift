//
//  Database.swift
//  MongoKitten
//
//  Created by Robbert Brandsma on 24-05-18.
//

import BSON
import Foundation
import NIO

/// A reference to a MongoDB database, over a `Connection`.
///
/// Databases hold collections of documents.
public class Database: FutureConvenienceCallable {
    internal var transaction: Transaction!
    
    /// The name of the database
    public let name: String
    
    /// The connection the database instance uses
    let session: ClientSession
    
    /// The collection to execute commands on
    internal var cmd: Collection {
        return self["$cmd"]
    }
    
    /// The ObjectId generator tied to this datatabase
    public var objectIdGenerator: ObjectIdGenerator {
        return session.cluster.sharedGenerator
    }
    
    public var cluster: Cluster {
        return session.cluster
    }
    
    /// The NIO event loop.
    public var eventLoop: EventLoop {
        return session.cluster.eventLoop
    }
    
    /// A helper method that uses the normal `connect` method and awaits it. It creates an event loop group for you.
    ///
    /// It is not recommended to use `synchronousConnect` in a NIO environment (like Vapor 3), as it will create an event loop group for you.
    ///
    /// - parameter uri: A MongoDB URI that contains at least a database component
    /// - throws: Can throw for a variety of reasons, including an invalid connection string, failure to connect to the MongoDB database, etcetera.
    /// - returns: A connected database instance
    public static func synchronousConnect(_ uri: String) throws -> Database {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        return try self.connect(uri, on: group.next()).wait()
    }
    
    /// Connect to the database at the given `uri`
    ///
    /// Will postpone queries until initial discovery is complete. Since the cluster is lazily initialized, you'll only know of a failure in connecting (such as wrong credentials) during queries
    ///
    /// - parameter uri: A MongoDB URI that contains at least a database component
    /// - parameter loop: An EventLoop from NIO. If you want to use MongoKitten in a synchronous / non-NIO environment, use the `synchronousConnect` method.
    public static func connect(_ uri: String, on loop: EventLoop) -> EventLoopFuture<Database> {
        do {
            let settings = try ConnectionSettings(uri)
            
            return connect(settings: settings, on: loop)
        } catch {
            return loop.newFailedFuture(error: error)
        }
    }
    
    /// Connect to the database at the given `uri`
    ///
    /// - parameter uri: A MongoDB URI that contains at least a database component
    /// - parameter loop: An EventLoop from NIO. If you want to use MongoKitten in a synchronous / non-NIO environment, use the `synchronousConnect` method.
    public static func lazyConnect(_ uri: String, on loop: EventLoop) throws -> Database {
        let settings = try ConnectionSettings(uri)
        return try lazyConnect(settings: settings, on: loop)
    }
    
    /// Connect to the database with the given settings. You can also use `connect(_:on:)` to connect by using a connection string.
    ///
    /// - parameter settings: The connection settings, which must include a database name
    /// - parameter loop: An EventLoop from NIO. If you want to use MongoKitten in a synchronous / non-NIO environment, use the `synchronousConnect` method.
    public static func connect(settings: ConnectionSettings, on loop: EventLoop) -> EventLoopFuture<Database> {
        do {
            guard let targetDatabase = settings.targetDatabase else {
                throw MongoKittenError(.unableToConnect, reason: .noTargetDatabaseSpecified)
            }
            
            return Cluster.connect(on: loop, settings: settings).map { cluster in
                return cluster[targetDatabase]
            }
        } catch {
            return loop.newFailedFuture(error: error)
        }
    }
    
    /// Connect to the database with the given settings _lazily_. You can also use `connect(_:on:)` to connect by using a connection string.
    ///
    /// Will postpone queries until initial discovery is complete. Since the cluster is lazily initialized, you'll only know of a failure in connecting (such as wrong credentials) during queries
    ///
    /// - parameter settings: The connection settings, which must include a database name
    /// - parameter loop: An EventLoop from NIO. If you want to use MongoKitten in a synchronous / non-NIO environment, use the `synchronousConnect` method.
    public static func lazyConnect(settings: ConnectionSettings, on group: EventLoopGroup) throws -> Database {
        guard let targetDatabase = settings.targetDatabase else {
            throw MongoKittenError(.unableToConnect, reason: .noTargetDatabaseSpecified)
        }
        
        return try Cluster(lazyConnectingTo: settings, on: group)[targetDatabase]
    }

    internal init(named name: String, session: ClientSession) {
        self.name = name
        self.session = session
    }
    
    /// Stats a new session which can be used for retryable writes, transactions and more
//    public func startSession(with options: SessionOptions) -> Database {
//        let newSession = session.cluster.sessionManager.next(with: options, for: session.cluster)
//        return Database(named: name, session: newSession)
//    }
    
    /// Creates a new tranasction provided the SessionOptions and optional TransactionOptions
    ///
    /// The TransactionDatabase that is created can be used like a normal Database for queries within transactions _only_
    /// Creating a TransactionCollection is done the same way it's created with a normal Database.
    public func startTransaction(with options: SessionOptions, transactionOptions: TransactionOptions? = nil) throws -> TransactionDatabase {
        guard session.cluster.wireVersion?.supportsReplicaTransactions == true else {
            throw MongoKittenError(.unsupportedFeatureByServer, reason: nil)
        }
        
        let newSession = session.cluster.sessionManager.next(with: options, for: session.cluster)
        let transactionOptions = transactionOptions ?? options.defaultTransactionOptions ?? TransactionOptions()
        let transaction = Transaction(
            options: transactionOptions,
            transactionId: newSession.serverSession.nextTransactionNumber()
        )
        return TransactionDatabase(named: name, session: newSession, transaction: transaction)
    }
    
    /// Get a `Collection` by providing a collection name as a `String`
    ///
    /// - parameter collection: The collection/bucket to return
    ///
    /// - returns: The requested collection in this database
    public subscript(collection: String) -> MongoKitten.Collection {
        return Collection(named: collection, in: self)
    }
    
    /// Drops the current database, deleting the associated data files
    ///
    /// - see: https://docs.mongodb.com/manual/reference/command/dropDatabase
    public func drop() -> EventLoopFuture<Void> {
        let command = AdministrativeCommand(command: DropDatabase(), on: cmd)
        
        return command.execute(on: self["$cmd"]).map { _ in }
    }
    
    /// Lists all collections your user has knowledge of
    ///
    /// Returns them as a MongoKitten Collection with you can query
    public func listCollections() -> EventLoopFuture<[Collection]> {
        return ListCollections(inDatabase: self.name).execute(on: self["$cmd"]).then { cursor in
            return cursor.drain().thenThrowing { documents in
                let decoder = BSONDecoder()
                return try documents.map { document -> Collection in
                    let description = try decoder.decode(CollectionDescription.self, from: document)
                    return self[description.name]
                }
            }
        }
    }
}
