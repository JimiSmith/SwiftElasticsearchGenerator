import Foundation

enum Multiplicity {
    case none
    case one
    case many
}

enum ObjectType: String {
    case objectType = "struct"
    case enumType = "enum"
    case simpleType = "simple"
    case arrayType = "array"
    case simpleArrayType = "simple_array"
    case parameterType = "parameter"
}

class ElementChildDescription {
    let required: Bool
    let element: ElementDescription
    
    init(required: Bool, element: ElementDescription) {
        self.required = required
        self.element = element
    }
    
    func typeDescription(defaultValue: String? = nil) -> String {
        var defaultValueString = ""
        if let defaultValue = defaultValue {
            defaultValueString = " = \(defaultValue)"
        }
        let optionalString = self.required ? "" : "?"
        if self.element.type == .arrayType ||
            self.element.type == .simpleArrayType {
            return "\(element.key.snakeToCamelCaseName()): [\(element.typeName)]\(optionalString)\(defaultValueString)"
        } else {
            return "\(element.key.snakeToCamelCaseName()): \(element.typeName)\(optionalString)\(defaultValueString)"
        }
    }
}

class ElementDescription {
    let key: String
    let containerKey: String?
    let typeName: String
    let parentType: String?
    let type: ObjectType
    let options: [String]?
    let childrenMultiplicity: Multiplicity
    let allowedChildren: [ElementChildDescription]?
    let value: ElementChildDescription?
    
    init(dict baseDict: [String: Any], parameters: [String : Any]) throws {
        self.key = baseDict["key"] as! String
        var dict: [String : Any]
        
        if baseDict["type"] as? String == "parameter" {
            dict = parameters[self.key] as! [String : Any]
        } else {
            dict = baseDict
        }
        
        var params = parameters
        
        if let childParams = dict["parameters"] as? [String : [String : Any]] {
            params = parameters.merging(otherDictionary: childParams)
        }
        
        self.typeName = dict["typeName"] as! String
        self.parentType = dict["parent"] as? String
        self.type = ObjectType(rawValue: dict["type"] as! String)!
        
        switch self.type {
        case .objectType:
            self.options = nil
            var childrenDict: [[String : Any]]? = nil
            
            if dict.keys.contains("childContainer") {
                let childContainer = dict["childContainer"] as! [String : Any]
                self.containerKey = childContainer["key"] as? String
                dict["one_of"] = childContainer["one_of"]
                dict["any_of"] = childContainer["any_of"]
                
                if let value = childContainer["value"] as? [String : Any] {
                    self.value = try ElementChildDescription(required: true,
                                                             element: ElementDescription(dict: value, parameters: params))
                } else {
                    self.value = nil
                }
            } else {
                self.containerKey = nil
                self.value = nil
            }
            
            if dict.keys.contains("one_of") {
                self.childrenMultiplicity = .one
                childrenDict = dict["one_of"] as? [[String : Any]]
            } else if dict.keys.contains("any_of") {
                self.childrenMultiplicity = .many
                childrenDict = dict["any_of"] as? [[String : Any]]
            } else {
                self.childrenMultiplicity = .none
            }
            if let childrenDict = childrenDict {
                self.allowedChildren = try childrenDict.map { ElementChildDescription(required: ($0["required"] as? Bool) ?? false,
                                                                                      element: try ElementDescription(dict: $0, parameters: params)) }
            } else {
                self.allowedChildren = nil
            }
        case .enumType:
            self.childrenMultiplicity = .one
            self.options = dict["options"] as? [String]
            self.allowedChildren = nil
            self.containerKey = nil
            self.value = nil
        case .simpleType:
            fallthrough
        case .simpleArrayType:
            fallthrough
        case .parameterType:
            fallthrough
        case .arrayType:
            self.childrenMultiplicity = .one
            self.options = nil
            self.allowedChildren = nil
            self.containerKey = nil
            self.value = nil
        }
    }
    
    func addContentsToBuilder(codeBuilder: SourceCodeBuilder) {
        if self.type != .objectType && self.type != .enumType {
            return
        }
        let builder = SourceCodeClassBuilder()
        if let parentType = self.parentType {
            builder.addLine("public \(self.type.rawValue) \(self.typeName): \(parentType) {")
        } else {
            builder.addLine("public \(self.type.rawValue) \(self.typeName): String {")
        }
        builder.indent()
        switch self.type {
        case .objectType:
            switch self.childrenMultiplicity {
            case .one:
                builder.addLine("public let child: QueryItem")
            case .none:
                fallthrough
            case .many:
                if let containerKey = self.containerKey {
                    builder.addLine("public let \(containerKey.snakeToCamelCaseName()): String")
                    
                    if let value = self.value {
                        builder.addLine("public let \(value.typeDescription())")
                    }
                }
                if let allowedChildren = self.allowedChildren {
                    for child in allowedChildren {
                        builder.addLine("public let \(child.typeDescription())")
                    }
                }
            }
        case .enumType:
            if let options = self.options {
                for option in options {
                    builder.addLine("case \(option.snakeToCamelCaseName()) = \"\(option)\"")
                }
            }
        default:
            break
        }
        
        if self.type == .objectType {
            builder.addLine("")
            builder.addLine("public init(")
            builder.indent()
            switch self.childrenMultiplicity {
            case .one:
                builder.addLine("child: QueryItem")
            case .none:
                fallthrough
            case .many:
                if let containerKey = self.containerKey {
                    builder.addLine("\(containerKey.snakeToCamelCaseName()): String,")
                    if let value = self.value {
                        builder.addLine("\(value.typeDescription())")
                    }
                }
                if let allowedChildren = self.allowedChildren {
                    builder.addLines(allowedChildren.map { $0.typeDescription(defaultValue: $0.required ? nil : "nil") }, separator: ",")
                }
            }
            builder.unIndent()
            builder.addLine(") {")
            builder.indent()
            switch self.childrenMultiplicity {
            case .one:
                builder.addLine("self.child = child")
            case .none:
                fallthrough
            case .many:
                if let containerKey = self.containerKey {
                    builder.addLine("self.\(containerKey.snakeToCamelCaseName()) = \(containerKey.snakeToCamelCaseName())")
                    
                    if let value = self.value {
                        builder.addLine("self.\(value.element.key.snakeToCamelCaseName()) = \(value.element.key.snakeToCamelCaseName())")
                    }
                }
                if let allowedChildren = self.allowedChildren {
                    for child in allowedChildren {
                        builder.addLine("self.\(child.element.key.snakeToCamelCaseName()) = \(child.element.key.snakeToCamelCaseName())")
                    }
                }
            }
            builder.unIndent()
            builder.addLine("}")
            
            builder.addLine("")
            builder.addLine("public func asJson() -> [String: Any] {")
            builder.indent()
            
            if self.childrenMultiplicity == .one {
                builder.addLine("return [\"\(self.key)\": self.child.asJson()]")
            } else {
                func getDictValue(_ element: ElementDescription) -> String {
                    if element.type == .objectType {
                        return "\(element.key.snakeToCamelCaseName()).asJson()"
                    } else if element.type == .enumType {
                        return "\(element.key.snakeToCamelCaseName()).rawValue"
                    } else if element.type == .simpleArrayType {
                        return "\(element.key.snakeToCamelCaseName())"
                    } else if element.type == .arrayType {
                        return "\(element.key.snakeToCamelCaseName()).map { $0.asJson() }"
                    }
                    return element.key.snakeToCamelCaseName()
                }
                
                if let allowedChildren = self.allowedChildren {
                    var dictPrefixString: String
                    if let containerKey = self.containerKey {
                        builder.addLine("var containerDict = [self.\(containerKey): [:]]")
                        dictPrefixString = "containerDict[self.\(containerKey)]?"
                    } else {
                        builder.addLine("var dict = [\"\(self.key)\": [:]]")
                        dictPrefixString = "dict[\"\(self.key)\"]?"
                    }
                    for child in allowedChildren {
                        let element = child.element
                        if child.required {
                            builder.addLine("\(dictPrefixString)[\"\(element.key)\"] = self.\(getDictValue(element))")
                        } else {
                            builder.addLine("if let \(element.key.snakeToCamelCaseName()) = self.\(element.key.snakeToCamelCaseName()) {")
                            builder.indent()
                            builder.addLine("\(dictPrefixString)[\"\(element.key)\"] = \(getDictValue(element))")
                            builder.unIndent()
                            builder.addLine("}")
                        }
                    }
                    if self.containerKey != nil {
                        builder.addLine("return [\"\(self.key)\": containerDict]")
                    } else {
                        builder.addLine("return dict")
                    }
                } else if let value = self.value {
                    if let containerKey = self.containerKey {
                        builder.addLine("return [\"\(self.key)\": [self.\(containerKey.snakeToCamelCaseName()): self.\(value.element.key.snakeToCamelCaseName())]]")
                    }
                } else {
                    builder.addLine("return [\"\(self.key)\": [:]]")
                }
            }
            
            builder.unIndent()
            builder.addLine("}")
            builder.addLine("")
        }
        
        builder.unIndent()
        builder.addLine("}")
        builder.addLine("")
        codeBuilder.addClass(name: self.typeName, cls: builder)
        if let allowedChildren = self.allowedChildren {
            for child in allowedChildren {
                child.element.addContentsToBuilder(codeBuilder: codeBuilder)
            }
        }
    }
    
    func asSwiftString() -> String {
        let builder = SourceCodeBuilder()
        self.addContentsToBuilder(codeBuilder: builder)
        return builder.build()
    }
}
