const std = @import("std");

const common = @import("../common.zig");
const NodeId = common.NodeId;
const ast = @import("../parse/ast.zig");

allocator: std.mem.Allocator,

// This works like a map that maps NodeId -> NodeId.
// To get referenced NodeId, just access index of referencing NodeId.
// For example in this scenario:
// ```brr
// const x = add(2, 2);
// fn add(a, b) { return a + b; }
// ```
// Identifier `add` in the first line will be referencing `add` function in the following line.
// undefined is used as null to limit memory usage. (idk if zig could figure this out by itself)
//
// Definitions cannot reference anything else, so in their case this points to scope id.
references: []NodeId,

// List of scopes in this metadata.
// Scopes may point to each other in some scenarios like this:
// ```
// import "hello.brr" as hello;
// ```
// In the example above `hello` is another scope based on "hello.brr" module.
// Same thing is with static methods on structs.
// In such cases both known_nodes and known_scopes will be populated.
scopes: std.ArrayList(Scope),
current_scope: usize = GLOBAL,
pub const GLOBAL = 0;

const Scope = struct {
    allocator: std.mem.Allocator,

    // This maps every known name to its declaring/defining node.
    known_names: std.StringHashMap(NodeId),
    parent: usize,

    pub fn init(allocator: std.mem.Allocator, parent: usize) Scope {
        return Scope{
            .allocator = allocator,
            .known_names = .init(allocator),
            .parent = parent,
        };
    }
    pub fn deinit(self: *Scope) void {
        self.known_names.deinit();
    }
};

const Self = @This();
pub fn init(allocator: std.mem.Allocator, tree: *common.Tree(ast.Node)) !Self {
    var self = Self{
        .allocator = allocator,
        .references = try allocator.alloc(NodeId, tree.nodes.items.len),
        .scopes = .init(allocator),
    };
    try self.scopes.append(Scope.init(allocator, GLOBAL));
    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.references);
    for (self.scopes.items) |*scope| {
        scope.deinit();
    }
    self.scopes.deinit();
}

pub fn reset(self: *Self) void {
    self.current_scope = GLOBAL;
}

pub fn pushScope(self: *Self) !usize {
    try self.scopes.append(Scope.init(self.allocator, self.current_scope));
    self.current_scope = self.scopes.items.len - 1;
    return self.current_scope;
}

pub fn enterScope(self: *Self, scope: usize) void {
    self.current_scope = scope;
}

pub fn popScope(self: *Self) usize {
    self.current_scope = self.scopes.items[self.current_scope].parent;
    return self.current_scope;
}
pub fn getScope(self: *Self, id: usize) *Scope {
    return &self.scopes.items[id];
}

pub inline fn currentScope(self: *Self) *Scope {
    return self.getScope(self.current_scope);
}

pub fn findName(self: *Self, name: []const u8) ?NodeId {
    var current_id = self.current_scope;
    var current = &self.scopes.items[current_id];
    while (true) {
        if (current.known_names.get(name)) |found|
            return found;
        if (current.parent != current_id) {
            current_id = current.parent;
            current = &self.scopes.items[current_id];
            continue;
        }

        return null;
    }
}
