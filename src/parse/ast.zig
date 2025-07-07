const std = @import("std");

const common = @import("../common.zig");
pub const PrettyPrinter = @import("../utility/AstPrettyPrinter.zig");

// Type alias for AST Tree.
pub const Tree = common.Tree(Node);

// Main structure for the AST node.
pub const Node = struct {
    span: common.Span,
    kind: NodeKind,
};

// Kind of AST node.
// Every kind is different when it comes to what it represents and stores.
pub const NodeKind = union(enum) {
    // ---< Basic nodes >---
    identifier: []const u8,
    // This is a standard string literal. Template literals will be separate.
    string_literal: []const u8,
    integer_literal: u64,
    float_literal: f64,
    boolean_literal: bool,
    parameter: Parameter,
    native_parameter: NativeParameter,
    code_block: []const NodeId,

    // --< Operator nodes >---
    binary_operator: BinaryOperator,
    unary_operator: UnaryOperator,
    assignment: Assignment,
    expression_group: ExpressionGroup,

    // ---< Special nodes >---
    module: Module,

    // ---< Statement nodes >---
    import: Import,
    function_def: FunctionDef,
    native_function_decl: NativeFunctionDecl,
    variable: Variable,
    constant: Const,
    loop: Loop,

    // ---< Expression nodes >---
};

pub const NodeId = usize;

// ---< AST Nodes begin >---
// All AST node structs should be located in this section of code.
// Non-basic nodes should only ever contain references to other nodes.

// Module statement. This node is special, because it has
// no corresponding langauge syntax. This is just a wrapper
// to provide one ID with whole top-level code.
pub const Module = struct {
    body: NodeId,
};

// Import statement. This is equivalent to one of the examples below:
// `import "source.brr";`
// `import "source.brr" as source;`
pub const Import = struct {
    source: NodeId,
    opt_rename: ?NodeId = null,
};
// Variable declaration. This is equivalent to the following code:
// brr [var name] = [expression];
pub const Variable = struct {
    name: NodeId,
    expression: NodeId,
};

//Const declaration. This is equivalent to the following code:
//const [name] = [expression];
pub const Const = struct {
    name: NodeId,
    expression: NodeId,
};
// Function definition. This is equivalent to the following code:
// `fn name(arg1, arg2) { ... }`
// Native functions are defined by NativeFunctionDecl.
pub const FunctionDef = struct {
    name: NodeId,
    parameters: []const NodeId,
    body: NodeId,
};

// Function parameter, this is currently only identifier.
// But for purposes of extensibility (and future-proofing attributes),
// this is what function definitions hold.
pub const Parameter = struct {
    name: NodeId,
};

// Native function declaration. This is equivalent to the following code:
// `native "C" fn name(arg1, arg2: i32);`
pub const NativeFunctionDecl = struct {
    abi: ?NodeId,
    name: NodeId,
    parameters: []const NodeId,
};

// Parameter for native function. This is different from standard parameter
// because it also can contain native type name.
// If no type is provided this is equivalent to passing interpreters value pointer
// and assuming this function is made specifically for Patapim language.
pub const NativeParameter = struct {
    name: NodeId,
    type: ?NodeId,
};

// Loop node. This is equivalent to the following code:
// `loop { ... }`
// This is a special node, because it has no condition.
pub const Loop = struct {
    body: NodeId,
};

// Binary operator node. This is equivalent to the following code:
// `left + right`
pub const BinaryOperator = struct {
    left: NodeId,
    operator: Operator,
    right: NodeId,
};

// Unary operator node. This is equivalent to the following code:
// `operator operand`
pub const UnaryOperator = struct {
    operator: Operator,
    operand: NodeId,
};

// This is equivalent to the following code:
// `variable_name = value`
pub const Assignment = struct {
    target: NodeId,
    operator: AssignmentOperator,
    value: NodeId, // Expression
};

pub const ExpressionGroup = struct {
    expression: NodeId,
};
// ---< AST Nodes end >---

// Operators are used in binary and unary operator nodes.
// They are used to represent the operator itself, and not the whole expression.
pub const Operator = enum {
    // Arithmetic operators
    ADD, // '+'
    SUBTRACT, // '-'
    MULTIPLY, // '*'
    DIVIDE, // '/'
    MODULO, // '%'

    // Comparison operators
    EQ_EQ, // '=='
    NOT_EQ, // '!='
    LESS_THAN, // '<'
    LESS_EQUAL, // '<='
    GREATER_THAN, // '>'
    GREATER_EQUAL, // '>='

    // Logical operators
    LOGICAL_AND, // '&&'
    LOGICAL_OR, // '||'

    // Shift operators
    BITSHIFT_LEFT, // '<<'
    BITSHIFT_RIGHT, // '>>'

    // Bitwise operators
    BITWISE_AND, // '&'
    BITWISE_OR, // '|'
    BITWISE_XOR, // '^'

    NOT, // '!'
    BITWISE_NOT, // '~'

    // Increment/Decrement operators
    INCREMENT, // '++'
    DECREMENT, // '--'

    UNKNOWN,
};

// Assigment operator.
// This is used to represent the operator itself, and not the whole expression.
pub const AssignmentOperator = enum {
    ASSIGN, // '='
    ADD_ASSIGN, // '+='
    SUB_ASSIGN, // '-='
    MUL_ASSIGN, // '*='
    DIV_ASSIGN, // '/='
    MOD_ASSIGN, // '%='
    BITWISE_AND_ASSIGN, // '&='
    BITWISE_OR_ASSIGN, // '|='
    BITWISE_XOR_ASSIGN, // '^='

    UNKNOWN,
};
