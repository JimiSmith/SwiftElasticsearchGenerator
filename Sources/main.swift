import Foundation

struct BodyDescription {
    var required = false
    var serialize: String? = nil
}

enum ParamType: String {
    case string = "string"
    case list = "list"
    
    func asSwiftType() -> String {
        switch self {
        case .string:
            return "String"
        case .list:
            return "[String]"
        }
    }
}

struct UrlParamDescription {
    let type: ParamType
    let description: String
}

struct UrlDescription {
    let path: [String]
    let params: [String: UrlParamDescription]
}

struct RequestExtensionDescription {
    let name: String
    let urls: [UrlDescription]
    let methods: [String]
    let body: BodyDescription?
    let documentation: String
    
    func asSwiftString() -> String {
        var classString = "extension Request {\n"
        for url in urls {
            var skip = false
            var params = url.path
                .map { $0.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "") }
                .map { ($0, url.params[$0]) }
                .filter { $1 != nil }
                .map { "\($0): \($1!.type.asSwiftType())" }
            
            params.append("method: HttpMethod = .\(self.methods.first!)")
            if let body = self.body {
                params.append("body: ElasticsearchBody\(body.required ? "" : "?")")
            }
            let path = url.path
                .map({ (item) -> String in
                    let paramName = item
                        .replacingOccurrences(of: "{", with: "")
                        .replacingOccurrences(of: "}", with: "")
                    if let param = url.params[paramName] {
                        if param.type == .list {
                            return "\\(\(paramName).joined(separator: \",\"))"
                        }
                        return "\\(\(paramName))"
                    }
                    if item == "_aliases" ||
                        item == "_warmers" ||
                        item == "_mappings" ||
                        item == "hotthreads" {
                        skip = true
                    }
                    return item
                })
                .joined(separator: "/")
            
            if path.hasPrefix("/_cluster/nodes") ||
                path.hasSuffix("/\\(type)/_mapping") ||
                path.hasPrefix("/_update_by_query") {
                skip = true
            }
            
            if skip {
                continue
            }
            
            // the typed method
            classString += "    /**\n"
            classString += "     * \(documentation)\n"
            for param in url.params {
                classString += "     * - parameter \(param.key): \(param.value.description)\n"
            }
            classString += "     * - parameter method: The http method used to execute the request\n"
            if self.body != nil {
                classString += "     * - parameter body: The body to be sent with the request\n"
            }
            classString += "     */\n"
            classString += "    public static func \(name.replacingOccurrences(of: ".", with: "_"))(\(params.joined(separator: ", "))) -> Request {\n"
            classString += "        assert(\(methods.map { "method == .\($0)" }.joined(separator: " || ")))\n"
            classString += "        let url = \"\(path)\"\n"
            if self.body != nil {
                if self.body!.required {
                    classString += "        return Request(method: (method == .GET ? .POST : method), url: url, body: body.asJson())\n"
                } else {
                    classString += "        return Request(method: (method == .GET ? .POST : method), url: url, body: body?.asJson())\n"
                }
            } else {
                classString += "        return Request(method: method, url: url, body: nil)\n"
            }
            classString += "    }\n\n"
            
            if self.body != nil {
                // body as dictionary
                classString += "    /**\n"
                classString += "     * \(documentation)\n"
                for param in url.params {
                    classString += "     * - parameter \(param.key): \(param.value.description)\n"
                }
                classString += "     * - parameter method: The http method used to execute the request\n"
                classString += "     * - parameter body: The body to be sent with the request\n"
                classString += "     */\n"
                classString += "    public static func \(name.replacingOccurrences(of: ".", with: "_"))(\(params.joined(separator: ", ").replacingOccurrences(of: "ElasticsearchBody", with: "[String : Any]"))) -> Request {\n"
                classString += "        assert(\(methods.map { "method == .\($0)" }.joined(separator: " || ")))\n"
                classString += "        let url = \"\(path)\"\n"
                classString += "        return Request(method: (method == .GET ? .POST : method), url: url, body: body)\n"
                classString += "    }\n"
            }
        }
        classString += "}"
        return classString
    }
}

func main() {
    var args = ProcessInfo.processInfo.arguments
    args.removeFirst()
    guard let inDir = args.filter({!$0.hasPrefix("-")}).first,
        let outDir = args.filter({!$0.hasPrefix("-")}).last else {
            exit(1)
    }
    guard let files = try? getAllInputFiles(inDir: inDir) else {
        exit(1)
    }
    
    guard let jsonObjects = try? getJSONFromFiles(files: files) else {
        exit(1)
    }
    
    guard let descriptions = try? parseJSONObjects(jsonObjects: jsonObjects) else {
        exit(1)
    }
    
    for description in descriptions {
        let filename = URL(fileURLWithPath: "\(description.name).swift", relativeTo: URL(fileURLWithPath: outDir))
        let contents = description.asSwiftString()
        try! contents.write(to: filename, atomically: true, encoding: .utf8)
    }
}
/**
 * test
 * - parameter inDir: A test
 */
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

func parseJSONObjects(jsonObjects: [String : Any]) throws -> [RequestExtensionDescription] {
    let regex = try NSRegularExpression(pattern: "(\\{[^}]+\\})", options: [])
    return jsonObjects.map({ (key, value) -> RequestExtensionDescription in
        let dict = value as! [String : Any]
        let url = dict["url"] as! [String : Any]
        let paths = url["paths"] as! [String]
        let parts = url["parts"] as? [String : Any]
        let urls = paths.map({ (path) -> UrlDescription in
            let params = regex.matches(in: path, options: [], range: NSMakeRange(0, (path as NSString).length))
                .map({ (result: NSTextCheckingResult) -> (String, UrlParamDescription)? in
                    if result.range.location == NSNotFound {
                        return nil
                    }
                    let name = (path as NSString).substring(with: result.range)
                        .replacingOccurrences(of: "{", with: "")
                        .replacingOccurrences(of: "}", with: "")
                    if let details = parts?[name] as? [String : Any] {
                        return (name, UrlParamDescription(type: ParamType.init(rawValue: details["type"] as! String)!,
                                                          description: details["description"] as! String))
                    } else {
                        return nil
                    }
                })
                .filter { $0 != nil }
                .reduce([String: UrlParamDescription]()) { result, current in
                    var newResult = result
                    newResult[current!.0] = current!.1
                    return newResult
            }
            
            return UrlDescription(path: path.components(separatedBy: "/"),
                                  params: params)
        })
        var body: BodyDescription? = nil
        
        if let bodyJson = dict["body"] as? [String : Any] {
            body = BodyDescription()
            body?.required = (bodyJson["required"] as? Bool) ?? false
            body?.serialize = bodyJson["serialize"] as? String
        }
        
        return RequestExtensionDescription(name: key,
                                           urls: urls,
                                           methods: dict["methods"] as! [String],
                                           body: body,
                                           documentation: dict["documentation"] as! String)
    })
}

main()
