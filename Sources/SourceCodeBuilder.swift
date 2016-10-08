import Foundation

class SourceCodeBuilder {
    private var classes = [String : SourceCodeClassBuilder]()
    
    func addClass(name: String, cls: SourceCodeClassBuilder) {
        if self.classes.keys.contains(name) &&
            self.classes[name]?.build() != cls.build() {
            print("Duplicate class name (\(name)) with different content detected. Aborting.")
            exit(1)
        }
        self.classes[name] = cls
    }
    
    func build() -> String {
        return self.classes.values.map { $0.build() }.joined(separator: "\n")
    }
}

class SourceCodeClassBuilder {
    private var lines = [String]()
    private var indentSpaces = 0
    
    func addLine(_ line: String) {
        self.lines.append(addIndent(string: line, spaces: self.indentSpaces))
    }
    
    func addLines(_ lines: [String], separator: String) {
        let total = lines.count
        var current = 0
        for line in lines {
            current += 1
            if current < total {
                self.lines.append("\(addIndent(string: line, spaces: self.indentSpaces))\(separator)")
            } else {
                self.lines.append("\(addIndent(string: line, spaces: self.indentSpaces))")
            }
        }
    }
    
    private func addIndent(string: String, spaces: Int) -> String {
        return "\(Array(repeating: " ", count: spaces).joined())\(string)"
    }
    
    func indent() {
        self.indentSpaces += 4
    }
    
    func unIndent() {
        self.indentSpaces -= 4
    }
    
    func build() -> String {
        return self.lines.joined(separator: "\n")
    }
}
