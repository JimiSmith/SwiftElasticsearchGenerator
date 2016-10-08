import Foundation

enum Mode: String {
    case apiSpec = "api"
    case requestSpec = "request"
}

func main() {
    var args = ProcessInfo.processInfo.arguments
    args.removeFirst()
    
    var mode: Mode = .apiSpec
    
    while args.first?.hasPrefix("-") ?? false {
        let arg = args.removeFirst()
        if arg == "--mode" || arg == "-m" {
            mode = Mode(rawValue: args.removeFirst())!
        }
    }
    
    guard let inDir = args.filter({!$0.hasPrefix("-")}).first,
        let outDir = args.filter({!$0.hasPrefix("-")}).last else {
            exit(1)
    }
    
    args.remove(at: args.index(of: inDir)!)
    args.remove(at: args.index(of: outDir)!)
    
    guard let files = try? getAllInputFiles(inDir: inDir) else {
        exit(1)
    }
    
    guard let jsonObjects = try? getJSONFromFiles(files: files) else {
        exit(1)
    }
    
    if mode == .apiSpec {
        guard let descriptions = try? parseApiJSONObjects(jsonObjects: jsonObjects) else {
            exit(1)
        }
        
        for description in descriptions {
            let filename = URL(fileURLWithPath: "\(description.name).swift", relativeTo: URL(fileURLWithPath: outDir))
            let contents = description.asSwiftString()
            try! contents.write(to: filename, atomically: true, encoding: .utf8)
        }
    } else {
        guard let descriptions = try? parseRequestBodyJSONObjects(jsonObjects: jsonObjects) else {
            exit(1)
        }
        
        for description in descriptions {
            let filename = URL(fileURLWithPath: "\(description.typeName).swift", relativeTo: URL(fileURLWithPath: outDir))
            let contents = description.asSwiftString()
            try! contents.write(to: filename, atomically: true, encoding: .utf8)
        }
    }
}

func getAllInputFiles(inDir: String) throws -> [URL] {
    return try FileManager.default.contentsOfDirectory(atPath: inDir)
        .filter { $0.hasSuffix(".json") }
        .map { URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: inDir)) }
}

func getJSONFromFiles(files: [URL]) throws -> [String : Any] {
    return try files.map({ (file) -> [String : Any] in
        let data = FileManager.default.contents(atPath: file.path)!
        return try JSONSerialization.jsonObject(with: data, options: []) as! [String : Any]
    }).reduce([String:Any]()) { result, current in
        var newResult = result
        newResult[current.keys.first!] = current.values.first!
        return newResult
    }
}

func parseApiJSONObjects(jsonObjects: [String : Any]) throws -> [RequestExtensionDescription] {
    return try jsonObjects.map({ (key, value) -> RequestExtensionDescription in
        try RequestExtensionDescription(key: key, value: value)
    })
}

func parseRequestBodyJSONObjects(jsonObjects: [String : Any]) throws -> [ElementDescription] {
    return try jsonObjects.map({ (key, value) -> ElementDescription in
        try ElementDescription(dict: value as! [String : Any], parameters: [:])
    })
}

main()
