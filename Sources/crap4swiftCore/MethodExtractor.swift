// SwiftSyntax tree to [MethodDescriptor]: every `func`, `init` and
// `subscript` declaration with a body becomes one descriptor.
//
// Names: `Type.function(parameterLabels)`, `Type.init`, `Type.subscript`.
// Free functions carry no type prefix; a local (nested) named func is its own
// entry, prefixed with its enclosing type/function chain. Closures are not
// descriptors — they count toward the enclosing method.

import SwiftParser
import SwiftSyntax

public struct MethodDescriptor {
    public let name: String
    public let startLine: Int
    public let endLine: Int
    /// The full declaration subtree; complexity is computed over it while
    /// skipping nested function declarations (they are their own entries).
    public let node: Syntax
}

public enum MethodExtractor {
    /// Parse `source` and extract the method descriptors in source order.
    public static func extract(source: String, fileName: String) -> [MethodDescriptor] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        let visitor = ExtractorVisitor(converter: converter)
        visitor.walk(tree)
        return visitor.descriptors
    }

    /// Complexity of a descriptor's body: decision points of the subtree,
    /// nested declarations excluded (they are separate entries).
    public static func complexity(of descriptor: MethodDescriptor) -> Int {
        ComplexityCalculator.complexity(of: descriptor.node)
    }
}

final class ExtractorVisitor: SyntaxVisitor {
    private(set) var descriptors: [MethodDescriptor] = []
    private var typeStack: [String] = []
    private var functionStack: [String] = []
    private let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(typeName(of: node.extendedType))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        let name = qualified(base: functionBaseName(node))
        appendDescriptor(name: name, node: Syntax(node))
        functionStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if node.body != nil { functionStack.removeLast() }
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        appendDescriptor(name: qualified(base: "init"), node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.accessorBlock != nil else { return .visitChildren }
        appendDescriptor(name: qualified(base: "subscript"), node: Syntax(node))
        return .visitChildren
    }

    private func appendDescriptor(name: String, node: Syntax) {
        let start = node.startLocation(converter: converter).line
        let end = node.endLocation(converter: converter).line
        descriptors.append(
            MethodDescriptor(name: name, startLine: start, endLine: end, node: node)
        )
    }

    /// `Type.local` chain + base name; top-level members have no local prefix.
    private func qualified(base: String) -> String {
        var parts = typeStack
        parts.append(contentsOf: functionStack)
        guard !parts.isEmpty else { return base }
        return parts.joined(separator: ".") + "." + base
    }
}

/// `name` for functions, `Type.init` for inits, `Type.subscript` for
/// subscripts (the type prefix is added by the caller).
private func typeName(of type: TypeSyntax) -> String {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    return type.trimmedDescription
}

/// Function base name with parameter labels: `foo(a:b:)`, `add(_:_:)`.
private func functionBaseName(_ node: FunctionDeclSyntax) -> String {
    let labels = node.signature.parameterClause.parameters.map { param in
        param.firstName.text + ":"
    }
    return node.name.text + "(" + labels.joined() + ")"
}
