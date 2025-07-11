const std = @import("std");

const common = @import("../common.zig");
const NodeId = common.NodeId;
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
    field_def: FieldDef,

    // --< Operator nodes >---
    binary_operator: BinaryOperator,
    unary_operator: UnaryOperator,
    assignment: Assignment,
    expression_group: ExpressionGroup,
    inline_conditional: InlineConditional,

    // ---< Special nodes >---
    module: Module,

    // ---< Statement nodes >---
    import: Import,
    function_def: FunctionDef,
    native_function_decl: NativeFunctionDecl,
    return_stmt: ReturnStatement,
    variable: Variable,
    constant: Const,
    loop: Loop,
    while_loop: WhileLoop,
    for_loop: ForLoop,
    struct_decl: StructDecl,
    enum_decl: EnumDecl,
    conditional: Conditional,
    expr_stmt: NodeId, // This is special statement wrapper for expressions as statements.
    break_stmt: void,
    continue_stmt: void,

    // ---< Expression nodes >---
    function_call: FunctionCall,
    member_access: MemberAccess,
    array_literal: ArrayLiteral,
    indexed_access: IndexedAccess,
    struct_literal: StructLiteral,
    variable_ref: NodeId,
};

// ---< AST Nodes begin >---
// All AST node structs should be located in this section of code.
// Non-basic nodes should only ever contain references to other nodes.

// Module statement. This node is special, because it has
// no corresponding langauge syntax. This is just a wrapper
// to provide one ID with whole top-level code.
pub const Module = struct {
    name: ?NodeId = null, // For named imports.
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
// `brr [var name] = [expression];`
pub const Variable = struct {
    name: NodeId,
    expression: NodeId,
};

//Const declaration. This is equivalent to the following code:
//`const [name] = [expression];`
pub const Const = struct {
    name: NodeId,
    expression: NodeId,
};

// Structure definition. This is equivalent to the following code:
// `struct [name] { field1, field2, ... }`
pub const StructDecl = struct {
    name: NodeId,
    fields: []const NodeId, // This is a list of fields.
    decls: []const NodeId, // This is a list of declarations.
};

// Enum definition. This is equivalent to following code:
// `enum [name] {field1, field2, ...}`
pub const EnumDecl = struct {
    name: NodeId,
    variants: []const NodeId, // This is a list of enumeration variants.
    decls: []const NodeId, // This is a list of declarations.
};

// Field for structure literal.
pub const FieldDef = struct {
    name: NodeId,
    value: NodeId,
};

// Structure literal. This is equivalent to the following code:
// `<target> { field1: value, field2: value }`
pub const StructLiteral = struct {
    target: ?NodeId, // If this is null, this is anonymous.
    fields: []const NodeId,
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

// This is a return statement. This is equivalent to the following code:
// `return [expression];`
pub const ReturnStatement = struct {
    value: ?NodeId, // This is the expression being returned.
};

// Loop node. This is equivalent to the following code:
// `loop { ... }`
// This is a special node, because it has no condition.
pub const Loop = struct {
    body: NodeId,
};

// While loop node. This is equivalent to the following code:
// `while(condition) { ... }`
pub const WhileLoop = struct {
    condition: NodeId,
    body: NodeId,
};

// For loop node. This is equivalent to the following code:
// `for (i in 0..10) { ... }`
pub const ForLoop = struct {
    binding: NodeId, // This is the variable that is bound to the loop.
    iterable: NodeId, // This is the iterable that is being looped over.
    body: NodeId,
};

pub const FunctionCall = struct {
    target: NodeId,
    arguments: []const NodeId,
};

pub const MemberAccess = struct {
    target: NodeId, // This is the object being accessed.
    member: NodeId, // This is the member being accessed.
};

// This is equivalent to `[a, b, c, ...d]`.
pub const ArrayLiteral = struct {
    elements: []const NodeId,
    spread: ?NodeId,
};

// This is `target[index]`.
pub const IndexedAccess = struct {
    target: NodeId,
    index: NodeId,
};

pub const Conditional = struct {
    condition: ?NodeId, // This is the condition being checked.
    body: NodeId, // This is the body of the conditional.
    else_conditional: ?NodeId = null, // This is the optional else if/else conditional.
};

pub const InlineConditional = struct {
    condition: NodeId, // This is the condition being checked.
    then_expr: NodeId, // This is the expression to evaluate if condition is true.
    else_expr: NodeId, // This is the expression to evaluate if condition is false.
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

// Expression group node. This is used to group expressions together.
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

    RANGE, // '..' (used in for loops)

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
