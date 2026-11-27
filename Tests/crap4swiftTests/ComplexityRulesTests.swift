// One test per complexity rule of the family table, plus the method-shape
// rules (closures count toward the enclosing method; nested named funcs are
// their own entries).

import Testing
@testable import crap4swiftCore

private func complexity(of source: String) -> Int {
    let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
    #expect(descriptors.count == 1)
    return MethodExtractor.complexity(of: descriptors[0])
}

private func complexity(_ label: String, _ body: String) -> Int {
    complexity(of: "func \(label)() {\n\(body)\n}")
}

struct ComplexityRulesTests {
    @Test func baseComplexityIsOne() {
        #expect(complexity("plain", "return 1") == 1)
    }

    @Test func ifStatement() {
        #expect(complexity("f", "if true { return 1 }\nreturn 2") == 2)
    }

    @Test func elseIfCountsAsOwnIf() {
        let code = """
        if true { return 1 } else if false { return 2 } else { return 3 }
        """
        #expect(complexity("f", code) == 3)
    }

    @Test func ifExpressionCountsAsIf() {
        #expect(complexity("f", "let x = if true { 1 } else { 2 }\nreturn x") == 2)
    }

    @Test func guardStatement() {
        #expect(complexity("f", "guard true else { return }\nreturn 1") == 2)
    }

    @Test func forLoop() {
        #expect(complexity("f", "for _ in 0..<3 { _ = 1 }") == 2)
    }

    @Test func whileLoop() {
        #expect(complexity("f", "while false { break }") == 2)
    }

    @Test func repeatLoop() {
        #expect(complexity("f", "repeat { break } while false") == 2)
    }

    @Test func catchClause() {
        let code = """
        do { _ = 1 } catch A { _ = 2 } catch B { _ = 3 } catch { _ = 4 }
        """
        #expect(complexity("f", code) == 4)
    }

    @Test func switchCasesAndDefault() {
        let code = """
        switch 1 {
        case 1: break
        case 2: break
        default: break
        }
        """
        #expect(complexity("f", code) == 4)
    }

    @Test func ternary() {
        #expect(complexity("f", "return true ? 1 : 2") == 2)
    }

    @Test func logicalAnd() {
        #expect(complexity("f", "return true && false") == 2)
    }

    @Test func logicalOr() {
        #expect(complexity("f", "return true || false") == 2)
    }

    @Test func nilCoalescing() {
        #expect(complexity("f", "let x: Int? = nil\nreturn x ?? 0") == 2)
    }

    @Test func combinedRules() {
        let code = """
        for _ in 0..<3 {
            if true && false { continue }
        }
        switch 1 { case 1: break; case 2: break }
        """
        // base 1 + for + if + && + 2 cases = 6
        #expect(complexity("f", code) == 6)
    }

    @Test func closuresCountTowardEnclosingMethod() {
        let code = """
        let items = [1, 2, 3]
        let doubled = items.map { $0 * 2 }
        _ = doubled.filter { $0 > 2 }
        """
        #expect(complexity("f", code) == 1)
    }

    @Test func closureBranchesCountTowardEnclosingMethod() {
        let code = """
        _ = [1, 2].map { value in
            if value > 1 { return value }
            return 0
        }
        """
        #expect(complexity("f", code) == 2)
    }

    @Test func nestedFuncIsOwnEntry() {
        let source = """
        func outer() {
            func inner() {
                if true { }
            }
            inner()
        }
        """
        let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
        #expect(descriptors.count == 2)
        let outer = descriptors.first { $0.name == "outer()" }
        let inner = descriptors.first { $0.name == "outer.inner()" }
        #expect(outer != nil && inner != nil)
        #expect(MethodExtractor.complexity(of: outer!) == 1)
        #expect(MethodExtractor.complexity(of: inner!) == 2)
    }

    @Test func optionalChainingAndOptionalTypesAreNotBranches() {
        let code = """
        let dict: [String: Int]? = [:]
        let value = dict?["x"]
        _ = value
        """
        #expect(complexity("f", code) == 1)
    }
}
