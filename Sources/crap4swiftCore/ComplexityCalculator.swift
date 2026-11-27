// Cyclomatic complexity rules (identical across the crap4 family).
//
// Base 1; +1 for each `if` (also `else if`), `guard`, `for`, `while`,
// `repeat`, `catch`, each `case` item of a `switch` (also `default`),
// ternary `? :`, `&&`, `||`, `??`.
//
// Closures count toward the enclosing method; nested named function
// declarations are skipped — they are their own entries.

import SwiftSyntax

public enum ComplexityCalculator {
    /// Complexity of a descriptor's subtree: the root declaration itself is
    /// not skipped (nested declarations are).
    public static func complexity(of node: Syntax) -> Int {
        let visitor = ComplexityVisitor()
        for child in node.children(viewMode: .sourceAccurate) {
            visitor.walk(child)
        }
        return visitor.score
    }
}

final class ComplexityVisitor: SyntaxVisitor {
    private(set) var score = 1

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    // Nested declarations are separate entries; their branches belong to
    // them, not to the enclosing method. (Initializers and subscripts can
    // never nest inside a function body, so only function declarations
    // need skipping.)
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    /// Swift's `if` statement and `if` expression share one syntax node in
    /// swift-syntax 600 (each `else if` is a nested node and counts again).
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    /// One point per `case` clause (`default` included).
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        bump(); return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if isLogicalOperator(node.operator.text) { bump() }
        return .visitChildren
    }

    private func bump() {
        score += 1
    }
}

private func isLogicalOperator(_ text: String) -> Bool {
    text == "&&" || text == "||" || text == "??"
}
