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
    
    init(key: String, value: Any) throws {
        let regex = try NSRegularExpression(pattern: "(\\{[^}]+\\})", options: [])
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
        
        self.name = key
        self.urls = urls
        self.methods = dict["methods"] as! [String]
        self.body = body
        self.documentation = dict["documentation"] as! String
    }
    
    func asSwiftString() -> String {
        let builder = SourceCodeClassBuilder()
        builder.addLine("extension Request {")
        builder.addLine("")
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
                            return "\\(\(paramName.snakeToCamelCaseName()).joined(separator: \",\"))"
                        }
                        return "\\(\(paramName.snakeToCamelCaseName()))"
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
            
            params = params.map { $0.snakeToCamelCaseName() }
            
            if path.hasPrefix("/_cluster/nodes") ||
                path.hasSuffix("/\\(type)/_mapping") ||
                path.hasPrefix("/_update_by_query") {
                skip = true
            }
            
            if skip {
                continue
            }
            
            // the typed method
            builder.indent()
            builder.addLine("/**")
            builder.addLine(" * \(documentation)")
            for param in url.params {
                builder.addLine(" * - parameter \(param.key.snakeToCamelCaseName()): \(param.value.description)")
            }
            builder.addLine(" * - parameter method: The http method used to execute the request")
            if self.body != nil {
                builder.addLine(" * - parameter body: The body to be sent with the request")
            }
            builder.addLine(" */")
            builder.addLine("public static func \(name.replacingOccurrences(of: ".", with: "_").snakeToCamelCaseName())(\(params.joined(separator: ", "))) -> Request {")
            builder.indent()
            builder.addLine("assert(\(methods.map { "method == .\($0)" }.joined(separator: " || ")))")
            builder.addLine("let url = \"\(path)\"")
            if self.body != nil {
                if self.body!.required {
                    builder.addLine("return Request(method: (method == .GET ? .POST : method), url: url, body: body.asJson())")
                } else {
                    builder.addLine("return Request(method: (method == .GET ? .POST : method), url: url, body: body?.asJson())")
                }
            } else {
                builder.addLine("return Request(method: method, url: url, body: nil)")
            }
            builder.unIndent()
            builder.addLine("}")
            builder.addLine("")
            
            if self.body != nil {
                // body as dictionary
                builder.addLine("/**")
                builder.addLine(" * \(documentation)")
                for param in url.params {
                    builder.addLine(" * - parameter \(param.key.snakeToCamelCaseName()): \(param.value.description)")
                }
                builder.addLine(" * - parameter method: The http method used to execute the request")
                builder.addLine(" * - parameter body: The body to be sent with the request")
                builder.addLine(" */")
                builder.addLine("public static func \(name.replacingOccurrences(of: ".", with: "_").snakeToCamelCaseName())(\(params.joined(separator: ", ").replacingOccurrences(of: "ElasticsearchBody", with: "[String : Any]"))) -> Request {")
                builder.indent()
                builder.addLine("assert(\(methods.map { "method == .\($0)" }.joined(separator: " || ")))")
                builder.addLine("let url = \"\(path)\"")
                builder.addLine("return Request(method: (method == .GET ? .POST : method), url: url, body: body)")
                builder.unIndent()
                builder.addLine("}")
                builder.addLine("")
            }
            builder.unIndent()
        }
        builder.addLine("}")
        builder.unIndent()
        return builder.build()
    }
}
