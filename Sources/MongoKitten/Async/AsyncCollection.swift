import Dispatch
import Schrodinger

public final class AsyncCollection : CollectionQueryable {
    var fullName: String {
        return "\(database.name).\(name)"
    }
    
    var name: String
    
    var database: Database
    
    var readConcern: ReadConcern?
    
    var writeConcern: WriteConcern?
    
    var collation: Collation?
    
    var timeout: DispatchTimeInterval?
    
    init(named name: String, in database: Database) {
        self.database = database
        self.name = name
    }
    
    public func findOne(_ query: Query? = nil, sortedBy sort: Sort? = nil, projecting projection: Projection? = nil, skipping skip: Int? = nil, readConcern: ReadConcern? = nil, collation: Collation? = nil) throws -> Future<Document?> {
        return try self.find(filter: query, sort: sort, projection: projection, readConcern: readConcern, collation: collation, skip: skip, limit: 1, timeout: nil, connection: nil).map { documents in
            return documents.next()
        }
    }
    
    public func find(_ filter: Query? = nil, sortedBy sort: Sort? = nil, projecting projection: Projection? = nil, readConcern: ReadConcern? = nil, collation: Collation? = nil, skipping skip: Int? = nil, limitedTo limit: Int? = nil, withBatchSize batchSize: Int = 100) throws -> Future<Cursor<Document>> {
        precondition(batchSize < Int(Int32.max))
        precondition(skip ?? 0 < Int(Int32.max))
        precondition(limit ?? 0 < Int(Int32.max))
        
        return try self.find(filter: filter, sort: sort, projection: projection, readConcern: readConcern, collation: collation, skip: skip, limit: limit, batchSize: batchSize, timeout: nil, connection: nil)
    }
}

extension Future {
    func await() throws -> T {
        return try self.await(for: .seconds(60))
    }
}
