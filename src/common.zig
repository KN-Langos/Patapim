const std = @import("std");

const reportz = @import("reportz");

// Span stores indices of where given token or node starts and ends.
pub const Span = struct {
    start: usize,
    end: usize,

    const Self = @This();

    pub fn len(span: Self) usize {
        return span.end - span.start;
    }

    pub inline fn asReportz(self: Self) reportz.reports.Span {
        return .{ .start = self.start, .end = self.end };
    }
};

// Template for trees. This is used by both AST and IR as their only difference is node set.
pub fn Tree(comptime Node: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        nodes: std.ArrayList(Node),

        const Self = @This();
        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .arena = .init(alloc),
                .nodes = .init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
            self.arena.deinit();
        }

        // Just a pretty way of getting arena allocator.
        // This is the same as calling `tree.arena.allocator()`.
        pub inline fn allocator(self: *Self) std.mem.Allocator {
            return self.arena.allocator();
        }

        // Appends new node to this tree returning its ID.
        pub fn addNode(self: *Self, node: Node) std.mem.Allocator.Error!usize {
            const old_len = self.nodes.items.len;
            try self.nodes.append(node);
            return old_len;
        }

        // Gets node from the tree. If node does not exists this returns null.
        pub fn getNode(self: *Self, id: usize) ?Node {
            if (self.nodes.items.len > id)
                return self.nodes.items[id];
            return null;
        }

        // Gets node from the tree with an assumption that it exists.
        // Avoid calling this, as it may cause segmentation faults.
        pub inline fn getNodeUnsafe(self: *Self, id: usize) Node {
            return self.nodes.items[id];
        }
    };
}

// Utility function to deeply copy a structure.
pub fn deepClone(comptime T: type, value: T, allocator: std.mem.Allocator) !T {
    return try cloneInner(T, value, allocator);
}

fn cloneInner(comptime T: type, value: T, allocator: std.mem.Allocator) !T {
    const info = @typeInfo(T);

    return switch (info) {
        .@"struct" => blk: {
            var result: T = undefined;

            inline for (std.meta.fields(T)) |field| {
                const field_val = @field(value, field.name);
                const cloned_val = try cloneInner(field.field_type, field_val, allocator);
                @field(result, field.name) = cloned_val;
            }

            break :blk result;
        },

        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => blk: {
                const len = value.len;
                const buf = try allocator.alloc(ptr_info.child, len);
                @memcpy(buf, value);
                break :blk buf;
            },

            .one => blk: {
                const ptr = try allocator.create(ptr_info.child);
                ptr.* = try cloneInner(ptr_info.child, value.*, allocator);
                break :blk ptr;
            },

            else => return error.UnsupportedPointerType,
        },

        .array => blk: {
            var arr: T = undefined;
            for (value, 0..) |elem, i| {
                arr[i] = try cloneInner(@TypeOf(elem), elem, allocator);
            }
            break :blk arr;
        },

        else => value, // Copy scalars, enums, etc. directly
    };
}
