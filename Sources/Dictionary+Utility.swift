import Foundation

extension Dictionary {
    func merging(otherDictionary other: [Key: Value]) -> [Key: Value] {
        return self.reduce(other, { (result, dictPair) -> [Key: Value] in
            var newResult = result
            newResult[dictPair.key] = dictPair.value
            return newResult
        })
    }
}
