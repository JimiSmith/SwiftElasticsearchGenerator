import Foundation

extension String {
    func snakeToCamelCaseName() -> String {
        let items = self.components(separatedBy: "_")
        var camelCase = ""
        items.enumerated().forEach {
            camelCase += 0 == $0 ? $1 : $1.capitalized
        }
        
        if camelCase == "operator" {
            return "`\(camelCase)`"
        }
        
        return camelCase
    }
}
