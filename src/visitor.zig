//! This file is composed of metaprogramming black magic and caffeine-powered spaghetti.
//! It relies heavily on compile time reflection to create generic `Visitor` for any tree.
//! Although we could have resolved this problem in a less strange way,
//! this is the most extensible approach to the problem, and can be reused in other projects that use zig.

const std = @import("std");

const common = @import("common.zig");

// Generic visitor for any tree.
// This assumes that `Node` structure contains `kind` field
// that is a union.
pub fn Visitor(
    comptime Node: type,
    comptime VisitorImpl: type,
    comptime ErrorSet: type,
    comptime default_return: anytype,
) type {
    const Tree = common.Tree(Node);
    if (!@hasField(Node, "kind"))
        @compileError("Node kind for visitor must contain 'kind' field.");
    const Return: type = if (@hasField(VisitorImpl, "Return"))
        @field(VisitorImpl, "Return")
    else
        void;

    return struct {
        const Self = @This();

        pub fn accept(self: *VisitorImpl, tree: *const Tree, node_id: usize) ErrorSet!Return {
            const node: Node = tree.getNodeUnsafe(node_id);
            const kind_tag = std.meta.activeTag(node.kind);

            switch (kind_tag) {
                inline else => |tag| {
                    const tag_name = @tagName(tag);
                    const visitor_fn_name = "visit" ++ comptime snakeToPascal(tag_name);
                    const value = @field(node.kind, tag_name);

                    const Variant = @TypeOf(value);
                    const visitee = Visitee(Tree, Variant, Self){
                        .value = value,
                        .impl = self,
                    };
                    if (comptime @hasDecl(VisitorImpl, visitor_fn_name)) {
                        const visit_fn = @field(VisitorImpl, visitor_fn_name);
                        try visit_fn(self, tree, node.span, value, visitee);
                    } else {
                        try visitee.walk(tree);
                        return default_return;
                    }
                },
            }
        }
    };
}

// Visitee is a single node kind with `walk` method implementation.
pub fn Visitee(
    comptime Tree: type,
    comptime Variant: type,
    comptime VisitorType: type,
) type {
    const info = @typeInfo(Variant);

    return struct {
        value: Variant,
        impl: *anyopaque,

        fn walkField(self: @This(), comptime field: anytype, tree: *const Tree, value: anytype) !void {
            switch (@typeInfo(field.type)) {
                .int => { // This is a pointer to another tree node.
                    _ = try VisitorType.accept(@ptrCast(self.impl), tree, value);
                },
                .optional => |_| {
                    if (value) |f| {
                        _ = try VisitorType.accept(@ptrCast(self.impl), tree, f);
                    }
                },
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .one => @compileError("All node child element IDs should be passed by value"),
                    .slice => {
                        for (value) |element| {
                            _ = try VisitorType.accept(@ptrCast(self.impl), tree, element);
                        }
                    },
                    else => @compileError("Only single pointers and slices are supported in walkField visitor."),
                },
                else => @compileError("All node variants should only have NodeIDs, optionals or slices."),
            }
        }

        pub fn walk(self: @This(), tree: *const Tree) !void {
            switch (info) {
                .@"struct" => |struct_info| {
                    inline for (struct_info.fields) |field| {
                        const value = @field(self.value, field.name);
                        try self.walkField(field, tree, value);
                    }
                },
                else => {},
            }
        }
    };
}

// Convert snake case to pascal case, this is used mainly for visitors.
fn snakeToPascal(comptime input: []const u8) []const u8 {
    var buf: [input.len]u8 = undefined;
    var out_idx: usize = 0;
    var capitalize = true;

    for (input) |c| {
        if (c == '_') {
            capitalize = true;
            continue;
        }
        buf[out_idx] = if (capitalize) std.ascii.toUpper(c) else c;
        out_idx += 1;
        capitalize = false;
    }

    return buf[0..out_idx];
}
