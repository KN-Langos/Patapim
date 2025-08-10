# Native Functions

Native functions allow Patapim to call compiled code from shared libraries, enabling high-performance operations and system-level integrations.

## Declaration Syntax
```
// Bind specific function from library
native "lib.so/add" fn myAdd();

// Bind specific function from library with the same name as a function name
native "lib.so" fn add();
```

### Supported Argument Types (Optional)
```
int       // Integer values
float     // Floating-point numbers
bool      // Boolean values
string    // Text data
function  // Callable functions
array     // Ordered collections
tuple     // Fixed-size mixed collections
unknown   // Dynamic typing (default)
```

### Implementation Requirements
Native libraries must implement the following:

**`RuntimeValue` Type (Zig example):**

```zig
pub const RuntimeValue = union(enum) {
    Integer: i64,
    Float: f64,
    Boolean: bool,
    String: []const u8,
    Array: std.ArrayList(RuntimeValue),
    Tuple: []const RuntimeValue,
    Void: void,
};
```

**Function Signature:**

```zig
export fn functionName(
    args: [*]const RuntimeValue, 
    args_len: usize, 
    result: *RuntimeValue
) callconv(.C) void;
```

### Complete Example
#### 1. Patapim Declaration
```
// Bind to math operations
native "math_ops.so" fn add(x, y);
native "math_ops.so" fn multiply(x, y);

// Type-annotated version
native "math_ops.so/subtract" fn sub(a: int, b: int);
```

#### 2. Zig Implementation (math_ops.zig)
```zig
const std = @import("std");

pub export fn add(args: [*]const RuntimeValue, args_len: usize, result: *RuntimeValue) callconv(.C) void {
    if (args_len != 2) @panic("add requires 2 arguments");
    
    const a = args[0].Integer;
    const b = args[1].Integer;
    
    result.* = .{ .Integer = a + b };
}

pub export fn multiply(args: [*]const RuntimeValue, args_len: usize, result: *RuntimeValue) callconv(.C) void {
    // ... similar implementation ...
}
```

#### 3. Building the Library
```bash
zig build-lib -dynamic -lc -O ReleaseFast math_ops.zig 
```

## Best Practices
### Argument Validation

```zig
if (args_len != expected_count) {
    @panic("Incorrect argument count");
}

if (args[0] != .Integer) {
    @panic("First argument must be integer");
}
```
