const common = @import("../common.zig");

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

    // ---< Statement nodes >---
    import: Import,

    // ---< Expression nodes >---
};

pub const NodeId = usize;

// ---< AST Nodes begin >---
// All AST node structs should be located in this section of code.
// Non-basic nodes should only ever contain references to other nodes.

// Import statement. This is equivalent to one of the examples below:
// `import "source.brr";`
// `import "source.brr" as source;`
pub const Import = struct {
    source: NodeId,
    opt_rename: ?NodeId,
};

// ---< AST Nodes end >---
