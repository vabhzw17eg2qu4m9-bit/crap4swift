// Method extraction: names (`Type.function(labels)`, `Type.init`,
// `Type.subscript`), extensions, line ranges, and the body requirement.

import Testing
@testable import crap4swiftCore

struct MethodExtractorTests {
    @Test func parameterLabelsInName() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { func doThing(with value: Int, and other: Int) { _ = value + other } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.doThing(with:and:)"])
    }

    @Test func unnamedLabelsUseUnderscore() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { func add(_ a: Int, _ b: Int) { _ = a + b } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.add(_:_:)"])
    }

    @Test func noParameters() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { func plain() { } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.plain()"])
    }

    @Test func initializerName() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { let x: Int; init(x: Int) { self.x = x } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.init"])
    }

    @Test func subscriptName() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { subscript(index: Int) -> Int { return index } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.subscript"])
    }

    @Test func freeFunctionHasNoTypePrefix() {
        let descriptors = MethodExtractor.extract(
            source: "func top() { }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["top()"])
    }

    @Test func extensionMethodsUseExtendedTypeName() {
        let descriptors = MethodExtractor.extract(
            source: "struct S { }; extension S { func go() { } }",
            fileName: "t.swift"
        )
        #expect(descriptors.map { $0.name } == ["S.go()"])
    }

    @Test func enumAndActorMethodsQualified() {
        let source = """
        enum E { func pick() { } }
        actor A { func perform() { } }
        """
        let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
        #expect(descriptors.map { $0.name } == ["E.pick()", "A.perform()"])
    }

    @Test func nestedTypesQualified() {
        let source = """
        class Outer {
            class Inner {
                func go() { }
            }
        }
        """
        let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
        #expect(descriptors.map { $0.name } == ["Outer.Inner.go()"])
    }

    @Test func declarationsWithoutBodyAreSkipped() {
        let source = """
        protocol P { func required() }
        struct S { func withBody() { } }
        """
        let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
        #expect(descriptors.map { $0.name } == ["S.withBody()"])
    }

    @Test func lineRangeSpansDeclaration() {
        let source = """
        struct S {
            func one() {
                let x = 1
                _ = x
            }
        }
        """
        let descriptors = MethodExtractor.extract(source: source, fileName: "t.swift")
        #expect(descriptors.count == 1)
        #expect(descriptors[0].startLine == 2)
        #expect(descriptors[0].endLine == 5)
    }
}
