//
// This source file is part of the MongoKitten open source project
//
// Copyright (c) 2016 - 2017 OpenKitten and the MongoKitten project authors
// Licensed under MIT
//
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/LICENSE.md for license information
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/CONTRIBUTORS.md for the list of MongoKitten project authors
//

import Foundation
import BSON

/// Message to be send or received to/from the server
enum Message {
    /// The MessageID this message is responding to
    /// Will always be 0 unless it's a `Reply` message
    /// - returns: The message ID we're responding to. Always `0` if this is not a reply message.
    var responseTo: Int32 {
        switch self {
        case .Reply(_, let responseTo, _, _, _, _, _):
            return responseTo
        default:
            return 0
        }
    }
    
    /// Returns the requestID for this message
    /// - returns: The requestID for this message
    var requestID: Int32 {
        switch self {
        case .Reply(let requestIdentifier, _, _, _, _, _, _):
            return requestIdentifier
        case .Update(let requestIdentifier, _, _, _, _):
            return requestIdentifier
        case .Insert(let requestIdentifier, _, _, _):
            return requestIdentifier
        case .Query(let requestIdentifier, _, _, _, _, _, _):
            return requestIdentifier
        case .GetMore(let requestIdentifier, _, _, _):
            return requestIdentifier
        case .Delete(let requestIdentifier, _, _, _):
            return requestIdentifier
        case .KillCursors(let requestIdentifier, _):
            return requestIdentifier
        }
    }
    
    /// Return the OperationCode for this message
    /// Some OPCodes aren't being used anymore since MongoDB only requires these 4 messages now
    /// - returns: The matching operation code for this message
    var operationCode: Int32 {
        switch self {
        case .Reply:
            return 1
        case .Update:
            return 2001
        case .Insert:
            return 2002
        case .Query:
            return 2004
        case .GetMore:
            return 2005
        case .Delete:
            return 2006
        case .KillCursors:
            return 2007
        }
    }
    
    /// Builds a `.Reply` object from Binary JSON
    /// - parameter from: The data to create a Reply-message from
    /// - returns: The reply instance
    static func makeReply(from data: Bytes) throws -> ServerReply {
        guard data.count > 4 else {
            throw DeserializationError.invalidDocumentLength
        }
        
        // Get the message length
        let length = Int32.make(data[0...3])
        
        // Check the message length
        if length != Int32(data.count) {
            throw DeserializationError.invalidDocumentLength
        }
        
        /// Get our variables from the message
        let requestID = Int32.make(data[4...7])
        let responseTo = Int32.make(data[8...11])
        
        let flags = Int32.make(data[16...19])
        let cursorID = Int(Int64.make(data[20...27]))
        let startingFrom = Int32.make(data[28...31])
        let numbersReturned = Int32.make(data[32...35])
        let documents = [Document](bsonBytes: data[36..<data.endIndex]*)
        
        // Return the constructed reply
        return ServerReply(requestID: requestID, responseTo: responseTo, flags: ReplyFlags.init(rawValue: flags), cursorID: cursorID, startingFrom: startingFrom, numbersReturned: numbersReturned, documents: documents)
    }
    
    /// Generates BSON From a Message
    /// - returns: The data from this message
    func generateData() throws -> Bytes {
        var body = Bytes()
        var requestID: Int32
        
        // Generate the body
        switch self {
        case .Reply:
            throw MongoError.internalInconsistency
        case .Update(let requestIdentifier, let collection, let flags, let findDocument, let replaceDocument):
            body += Int32(0).makeBytes()
            body += collection.cStringBytes
            body += flags.rawValue.makeBytes()
            body += findDocument.bytes
            body += replaceDocument.bytes
            
            requestID = requestIdentifier
        case .Insert(let requestIdentifier, let flags, let collection, let documents):
            body += flags.rawValue.makeBytes()
            body += collection.cStringBytes
            
            for document in documents {
                body += document.bytes
            }
            
            requestID = requestIdentifier
        case .Query(let requestIdentifier, let flags, let collection, let numbersToSkip, let numbersToReturn, let query, let returnFields):
            body += flags.rawValue.makeBytes()
            body += collection.cStringBytes
            body += numbersToSkip.makeBytes()
            body += numbersToReturn.makeBytes()
            
            body += query.bytes
            
            if let returnFields = returnFields {
                body += returnFields.bytes
            }
            
            requestID = requestIdentifier
        case .GetMore(let requestIdentifier, let namespace, let numberToReturn, let cursorID):
            body += Int32(0).makeBytes()
            body += namespace.cStringBytes
            body += numberToReturn.makeBytes()
            body += cursorID.makeBytes()
            
            requestID = requestIdentifier
        case .Delete(let requestIdentifier, let collection, let flags, let removeDocument):
            body += Int32(0).makeBytes()
            body += collection.cStringBytes
            body += flags.rawValue.makeBytes()
            body += removeDocument.bytes
            
            requestID = requestIdentifier
        case .KillCursors(let requestIdentifier, let cursorIDs):
            body += Int32(0).makeBytes()
            body += cursorIDs.map { $0.makeBytes() }.reduce([]) { $0 + $1 }
            
            requestID = requestIdentifier
        }
        
        // Generate the header using the body
        var header = Bytes()
        header += Int32(16 + body.count).makeBytes()
        header += requestID.makeBytes()
        header += responseTo.makeBytes()
        header += operationCode.makeBytes()
        
        return header + body
    }
    
    /// The Reply message that we can receive from the server
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter responseTo: The Client-side query/getmore that this message responds to
    /// - parameter flags: The flags that are given with this message
    /// - parameter cursorID: The cursor that can be used to fetch more information (if available)
    /// - parameter startingFrom: The position in this cursor to start
    /// - parameter numbersReturned: The amount of returned results in this reply
    /// - parameter documents: The documents that have been returned
    case Reply(requestID: Int32, responseTo: Int32, flags: ReplyFlags, cursorID: Int, startingFrom: Int32, numbersReturned: Int32, documents: [Document])
    
    /// Updates data on the server using an older method
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter collection: The collection we'll update information in
    /// - parameter flags: The flags to be sent with this message
    /// - parameter findDocument: The filter to use when finding documents to update
    /// - parameter replaceDocument: The Document to replace the results with
    case Update(requestID: Int32, collection: String, flags: UpdateFlags, findDocument: Document, replaceDocument: Document)
    
    /// Insert data into the server using an older method
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter flags: The flags to be sent with this message
    /// - parameter collection: The collection to insert information in
    /// - parameter documents: The documents to insert in the collection
    case Insert(requestID: Int32, flags: InsertFlags, collection: String, documents: [Document])
    
    /// Used for CRUD operations on the server.
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter flags: The flags to be sent with this message
    /// - parameter collection: The collection to query to
    /// - parameter numbersToSkip: How many results to skip before processing
    /// - parameter numberToReturn: The amount of results to return
    /// - parameter query: The query to execute. Can be a DBCommand.
    /// - parameter returnFields: The fields to return or to ignore
    case Query(requestID: Int32, flags: QueryFlags, collection: String, numbersToSkip: Int32, numbersToReturn: Int32, query: Document, returnFields: Document?)
    
    /// Get more data from the cursor's selected data
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter namespace: The namespace to get more information from like `mydatabase.mycollection` or `mydatabase.mybucket.mycollection`
    /// - parameter numbersToReturn: The amount of results to return
    /// - parameter cursor: The ID of the cursor that we will fetch more information from
    case GetMore(requestID: Int32, namespace: String, numberToReturn: Int32, cursor: Int)
    
    /// Delete data from the server using an older method
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter collection: The Collection to delete information from
    case Delete(requestID: Int32, collection: String, flags: DeleteFlags, removeDocument: Document)
    
    /// The message we send when we don't need the selected information anymore
    /// - parameter requestID: The Request ID that you can get from the server by calling `server.nextMessageID()`
    /// - parameter cursorIDs: The list of IDs that refer to cursors that need to be killed
    case KillCursors(requestID: Int32, cursorIDs: [Int])
}

struct ServerReplyPlaceholder {
    var totalLength: Int?
    var requestId: Int32?
    var responseTo: Int32?
    var opCode: Int32?
    var flags: ReplyFlags?
    var cursorID: Int?
    var startingFrom: Int32?
    var numbersReturned: Int32?
    var documentsData = [UInt8]()
    var unconsumed = [UInt8]()
    var documentsComplete = false
    
    var isComplete: Bool {
        guard let totalLength = totalLength else {
            return false
        }
        
        return requestId != nil && responseTo != nil && flags != nil && cursorID != nil && startingFrom != nil && numbersReturned != nil && documentsComplete && totalLength - 36 == documentsData.count
    }
    
    init() {
        // largest data (cursorID Int64) - 1 byte for not complete
        unconsumed.reserveCapacity(7)
    }
    
    mutating func process(consuming: UnsafeMutablePointer<UInt8>, withLengthOf length: Int) -> Int {
        var advanced = 0
        var consuming = consuming
        var length = length
        
        func require(_ n: Int) -> Bool {
            guard unconsumed.count + length >= n else {
                advanced = min(n &- unconsumed.count, length)
                let data = Array(UnsafeBufferPointer(start: consuming, count: advanced))
                self.unconsumed.append(contentsOf: data)
                consuming = consuming.advanced(by: advanced)
                
                return false
            }
            
            return true
        }
        
        func makeInt32() -> Int32? {
            guard require(4) else {
                return nil
            }
            
            if unconsumed.count > 0 {
                var data = [UInt8](repeating: 0, count: 4 - unconsumed.count)
                memcpy(&data, consuming, 4 - unconsumed.count)
                data = unconsumed + data
                
                advanced = 4 - unconsumed.count
                
                unconsumed.removeFirst(min(4, unconsumed.count))
                
                return Int32.make(data)
            } else {
                advanced = 4
                return consuming.withMemoryRebound(to: Int32.self, capacity: 1, { $0.pointee })
            }
        }
        
        func makeInt64() -> Int64? {
            guard require(8) else {
                return nil
            }
            
            if unconsumed.count > 0 {
                var data = [UInt8](repeating: 0, count: 8 - unconsumed.count)
                memcpy(&data, consuming, 8 - unconsumed.count)
                data = unconsumed + data
                
                advanced = 8 - unconsumed.count
                
                unconsumed.removeFirst(min(8, unconsumed.count))
                
                return Int64.make(data)
            } else {
                advanced = 8
                return consuming.withMemoryRebound(to: Int64.self, capacity: 1, { $0.pointee })
            }
        }
        
        if totalLength == nil {
            guard let totalLength = makeInt32() else {
                return advanced
            }
            
            self.totalLength = Int(totalLength) as Int
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if requestId == nil {
            guard let requestId = makeInt32() else {
                return advanced
            }
            
            self.requestId = requestId
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if responseTo == nil {
            guard let responseTo = makeInt32() else {
                return advanced
            }
            
            self.responseTo = responseTo
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if opCode == nil {
            guard let opCode = makeInt32() else {
                return advanced
            }
            
            self.opCode = opCode
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if flags == nil {
            guard let flag = makeInt32() else {
                return advanced
            }
            
            self.flags = ReplyFlags(rawValue: flag)
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if cursorID == nil {
            guard let cursorID = makeInt64() else {
                return advanced
            }
            
            self.cursorID = Int(cursorID)
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if startingFrom == nil {
            guard let startingFrom = makeInt32() else {
                return advanced
            }
            
            self.startingFrom = startingFrom
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        if numbersReturned == nil {
            guard let numbersReturned = makeInt32() else {
                return advanced
            }
            
            self.numbersReturned = numbersReturned
            
            return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
        }
        
        guard let totalLength = totalLength, let numbersReturned = numbersReturned else {
            return advanced
        }
        
        func checkDocuments() -> (count: Int, half: Int) {
            guard documentsData.count > 3 else {
                return (0, documentsData.count)
            }
            
            var count = 0
            var pos = 0
            
            while pos < documentsData.count {
                guard pos + 4 < documentsData.count else {
                    return (count, documentsData.count - pos)
                }
                
                let length = Int(Int32.make(documentsData[pos..<pos + 4]))
                
                guard pos + length <= documentsData.count else {
                    return (count, documentsData.count - pos)
                }
                
                pos += length
                count += 1
            }
            
            return (count, documentsData.count - pos)
        }
        
        @discardableResult
        func checkComplete(documentCount count: Int? = nil) -> Bool {
            let documentCount: Int
            
            if let count = count {
                documentCount = count
            } else {
                let (count, _) = checkDocuments()
                
                documentCount = count
            }
            
            if totalLength - 36 == documentsData.count, Int(numbersReturned) == documentCount {
                self.documentsComplete = true
                return true
            }
            
            return false
        }
        
        let (documentCount, halfComplete) = checkDocuments()
        
        if checkComplete(documentCount: documentCount) {
            return advanced
        }
        
        if halfComplete > 0 {
            let startOfDocument = documentsData.endIndex.advanced(by: -halfComplete)
            
            let documentLength = Int(Int32.make(documentsData[startOfDocument..<startOfDocument.advanced(by: 4)]))
            let neededLength = documentLength - halfComplete
            
            advanced = min(length, neededLength)
            
            documentsData.append(contentsOf: UnsafeBufferPointer<Byte>(start: consuming, count: advanced))
            
            guard length > neededLength else {
                checkComplete()
                
                return advanced
            }
        } else {
            let unconsumedCopy = unconsumed
            
            guard let documentLength = Int(makeInt32()) else {
                return length
            }
            
            advanced = min(length, documentLength - unconsumedCopy.count)
            documentsData.append(contentsOf: unconsumedCopy)
            documentsData.append(contentsOf: UnsafeBufferPointer<Byte>(start: consuming, count: advanced))
            
            guard length > documentLength else {
                checkComplete()
                
                return advanced
            }
        }
        
        return advanced + self.process(consuming: consuming.advanced(by: advanced), withLengthOf: length - advanced)
    }
    
    func construct() -> ServerReply? {
        guard
            let requestId = requestId,
            let responseTo = responseTo,
            let flags = flags,
            let cursorID = cursorID,
            let startingFrom = startingFrom,
            let numbersReturned = numbersReturned,
            documentsComplete else {
                return nil
        }
        
        let docs = [Document](bsonBytes: documentsData)
        
        return ServerReply(requestID: requestId, responseTo: responseTo, flags: flags, cursorID: cursorID, startingFrom: startingFrom, numbersReturned: numbersReturned, documents: docs)
    }
}

struct ServerReply {
    let requestID: Int32
    let responseTo: Int32
    let flags: ReplyFlags
    let cursorID: Int
    let startingFrom: Int32
    let numbersReturned: Int32
    var documents: [Document]
}

internal func fromBytes<T, S : Swift.Collection>(_ bytes: S) throws -> T where S.Iterator.Element == Byte, S.IndexDistance == Int {
    guard bytes.count >= MemoryLayout<T>.size else {
        throw DeserializationError.invalidElementSize
    }
    
    return UnsafeRawPointer(Bytes(bytes)).assumingMemoryBound(to: T.self).pointee
}

extension Int64 {
    internal static func make<S : Swift.Collection>(_ s: S) -> Int64 where S.Iterator.Element == UInt8, S.Index == Int {
        var number: Int64 = 0
        number |= s.count > 7 ? Int64(s[s.startIndex.advanced(by: 7)]) << 56 : 0
        number |= s.count > 6 ? Int64(s[s.startIndex.advanced(by: 6)]) << 48 : 0
        number |= s.count > 5 ? Int64(s[s.startIndex.advanced(by: 5)]) << 40 : 0
        number |= s.count > 4 ? Int64(s[s.startIndex.advanced(by: 4)]) << 32 : 0
        number |= s.count > 3 ? Int64(s[s.startIndex.advanced(by: 3)]) << 24 : 0
        number |= s.count > 2 ? Int64(s[s.startIndex.advanced(by: 2)]) << 16 : 0
        number |= s.count > 1 ? Int64(s[s.startIndex.advanced(by: 1)]) << 8 : 0
        number |= s.count > 0 ? Int64(s[s.startIndex.advanced(by: 0)]) << 0 : 0
        
        return number
    }
}

extension Int32 {
    internal static func make<S : Swift.Collection>(_ s: S) -> Int32 where S.Iterator.Element == UInt8, S.Index == Int {
        var val: Int32 = 0
        val |= s.count > 3 ? Int32(s[s.startIndex.advanced(by: 3)]) << 24 : 0
        val |= s.count > 2 ? Int32(s[s.startIndex.advanced(by: 2)]) << 16 : 0
        val |= s.count > 1 ? Int32(s[s.startIndex.advanced(by: 1)]) << 8 : 0
        val |= s.count > 0 ? Int32(s[s.startIndex]) : 0
        
        return val
    }
}
