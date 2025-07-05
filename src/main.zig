//! This file will contain the CLI tool for Patapim.
//! Main interpreter source code has root in `root.zig`

const std = @import("std");

const patapim = @import("patapim");

pub fn main() !void {
    std.debug.print("All your code belongs to Patapim!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const source =
        \\import "source.brr";
        \\import "another.brr" as another;
        \\fn hello(arg1, arg2) {}
        \\native "C" fn lorem(ipsum: int, dolor);
    ;
    var lexer: patapim.Lexer = .{ .source = source };
    var parser = patapim.Parser.init(allocator, &lexer);
    defer parser.deinit(true);

    const module = try parser.parseWholeSource();
    var printer = patapim.ast.PrettyPrinter{
        .writer = std.io.getStdOut().writer().any(),
        .print_spans = false,
    };
    try printer.accept(&parser.tree, module);
}
