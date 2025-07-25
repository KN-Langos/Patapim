const std = @import("std");

const ast = @import("../parse/ast.zig");
const Interpreter = @import("Interpreter.zig");

pub const Error = error{
    UndeclaredVariable,
    VariableAlreadyDeclared,
    CannotModifyImmutableVariable,
};

// Runtime values used during the execution of the program.
// These values are used in the interpreter and can be of different types.
// They are designed to be flexible and can represent integers, floats, booleans, and strings.
pub const RuntimeValue = union(enum) {
    Integer: i64,
    Float: f64,
    Boolean: bool,
    String: []const u8,
    Array: *std.ArrayList(RuntimeValue),
    Void: void,
    Function: FunctionValue,
    IntrinsicFunction: IntrinsicFunctionValue,

    // Converts the RuntimeValue to a string representation.
    // This is useful for debugging or displaying values.
    // It allocates memory for the string representation, so it should be used with care.
    pub fn toString(self: RuntimeValue, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .Integer => |i| std.fmt.allocPrint(allocator, "{}", .{i}),
            .Float => |f| std.fmt.allocPrint(allocator, "{}", .{f}),
            .Boolean => |b| std.fmt.allocPrint(allocator, "{}", .{b}),
            .String => |s| allocator.dupe(u8, s),
            .Array => |array| {
                var string = std.ArrayList(u8).init(allocator);
                defer string.deinit();

                try string.append('[');

                for (array.items, 0..) |element, index| {
                    const element_string = try toString(element, allocator);
                    defer allocator.free(element_string);

                    try string.appendSlice(element_string);

                    if (index != self.Array.items.len - 1) {
                        try string.append(',');
                    } else {
                        try string.append(']');
                    }
                }
                return string.toOwnedSlice();
            },
            .Void => allocator.dupe(u8, "void"),
            .Function => std.fmt.allocPrint(allocator, "Function with body id {}", .{self.Function.body_id}),
            .IntrinsicFunction => |ptr| std.fmt.allocPrint(allocator, "Intrinsic function at {*}", .{ptr.ptr}),
        };
    }
};

// FunctionValue represents a function in the runtime.
// It contains the parameters of the function, the body of the function,
// and the environment in which the function was defined.
pub const FunctionValue = struct {
    parameters: [][]const u8, // The parameters of the function.
    body_id: usize, // The function body node.
    environment: *Environment, // The environment in which the function was defined.
};

pub const IntrinsicFunctionValue = struct {
    ptr: *const fn (?RuntimeValue, []const RuntimeValue, *Environment) Interpreter.Error!RuntimeValue,
};

// VariableBinding represents a binding of a variable to a runtime value.
// It holds the value of the variable and a flag indicating if the variable is mutable.
// This is used in the environment to manage variable states during execution.
// The `is_mutable` field indicates whether the variable can be modified.
pub const VariableBinding = struct {
    value: RuntimeValue,
    is_mutable: bool, // Indicates if the variable can be modified.
};

// Environment represents a runtime environment that holds variable bindings.
// It is a stack of environments where each environment can have its own set of variable bindings.
// This allows for nested scopes and variable shadowing.
// The environment can be used to look up variable values during the execution of the program.
// It supports parent environments, allowing for variable lookups in outer scopes.
// The environment is mutable, allowing for variable assignments and updates.
// It uses a hash map to store variable names and their corresponding runtime values.
// The environment can be initialized with a parent environment, allowing for nested scopes.
// It can be deinitialized to free up resources.
// The environment can be used to get and set variable values, supporting both retrieval and assignment.
pub const Environment = struct {
    parent: ?*Environment,
    values: std.StringHashMap(VariableBinding),
    is_top_level: bool = false, // Indicates if this is the top-level environment.
    arena_allocator: std.heap.ArenaAllocator,
    this_context: ?RuntimeValue = null,

    // Initializes a new environment with an optional parent environment.
    // The parent environment allows for variable lookups in outer scopes.
    // It returns an error if the initialization fails.
    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment, is_top_level: bool) !Environment {
        return Environment{
            .parent = parent,
            .values = std.StringHashMap(VariableBinding).init(allocator),
            .is_top_level = is_top_level,
            .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        };
    }

    // Deinitializes the environment, freeing up resources.
    // It deinitializes the values hash map, which releases any allocated memory.
    // This should be called when the environment is no longer needed.
    pub fn deinit(self: *Environment) void {
        self.values.deinit();
        self.arena_allocator.deinit();
    }

    // Gets the value associated with the given key in the environment.
    // It first checks the current environment for the key.
    // If the key is not found, it checks the parent environment recursively.
    // If the key is not found in any environment, it returns null.
    pub fn get(self: *const Environment, key: []const u8) ?RuntimeValue {
        if (self.values.get(key)) |binding| return binding.value;
        if (self.parent) |parent_env| return parent_env.get(key);
        return null;
    }

    // Sets the value for the given key in the environment.
    // It updates the value in the current environment.
    // If the key does not exist, it adds a new entry.
    pub fn set(self: *Environment, key: []const u8, value: RuntimeValue) !void {
        if (self.values.getPtr(key)) |binding| {
            if (!binding.is_mutable) {
                return error.CannotModifyImmutableVariable;
            }
            binding.value = value;
            return;
        } else if (self.parent) |parent_env| {
            try parent_env.set(key, value); // Recurse upward if shadowed
        } else {
            return error.UndeclaredVariable;
        }
    }

    // Defines a new variable in the environment.
    // It checks if the variable already exists and returns an error if it does.
    // If the variable does not exist, it adds a new entry to the environment.
    pub fn define(self: *Environment, key: []const u8, value: RuntimeValue, is_mutable: bool) !void {
        if (self.values.contains(key)) {
            return error.VariableAlreadyDeclared;
        }
        // If the key already exists, we do not allow redefining it.
        // This is to prevent accidental overwriting of existing variables.
        try self.values.put(key, .{
            .value = value,
            .is_mutable = is_mutable,
        });
    }
};
