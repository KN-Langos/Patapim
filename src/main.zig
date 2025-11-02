//! This file will contain the CLI tool for Patapim.
//! Main interpreter source code has root in `root.zig`

const std = @import("std");

const zli = @import("zli");

const cli_root = @import("cli/root_cmd.zig");

pub const std_options = std.Options{ .log_level = .warn };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = false, // We are single-threaded rn.
    }){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root_command = try cli_root.build(allocator);
    defer root_command.deinit();

    try root_command.execute(.{});
}

// pub fn main() !void {
//     std.debug.print("All your code belongs to Patapim!\n", .{});

//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer std.debug.assert(gpa.deinit() == .ok);
//     const allocator = gpa.allocator();

//     // ---< Interpreter Test >---

//     // Open current directory
//     const cwd = std.fs.cwd();

//     // Open the source file
//     const file = try cwd.openFile("./src/test.brr", .{});
//     defer file.close();

//     // Read the file contents into a buffer
//     const source = try file.readToEndAlloc(allocator, 10_000); // 10 KB max
//     defer allocator.free(source);

//     var lexer: patapim.Lexer = .{ .source = source };
//     var parser = patapim.Parser.init(allocator, &lexer);
//     defer parser.deinit(true);

//     const module = try parser.parseWholeSource();

//     std.debug.print("\n\n---< AST >---\n\n", .{});
//     var printer = patapim.ast.PrettyPrinter{
//         .writer = std.io.getStdOut().writer().any(),
//         .print_spans = false,
//     };
//     try printer.accept(&parser.tree, module);

//     // std.debug.print("\n\n---< Analysis >---\n\n", .{});
//     // var metadata = try patapim.analysis.Metadata.init(allocator, &parser.tree);
//     // defer metadata.deinit();

//     // var item_name_binding_pass = patapim.analysis.ItemNameBindingPass{
//     //     .metadata = &metadata,
//     // };
//     // try item_name_binding_pass.accept(&parser.tree, module);

//     // var name_resolution_pass = patapim.analysis.NameResolutionPass{
//     //     .metadata = &metadata,
//     // };
//     // try name_resolution_pass.accept(&parser.tree, module);

//     std.debug.print("\n\n---< Interpreter >---\n\n", .{});
//     var interpreter = try patapim.Interpreter.init(allocator, &parser.tree);
//     defer interpreter.deinit();
//     try interpreter.interpret(module);
//     try interpreter.printDebugInfo();
// }
