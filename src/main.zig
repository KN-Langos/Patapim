//! This file will contain the CLI tool for Patapim.
//! Main interpreter source code has root in `root.zig`

const std = @import("std");

const patapim = @import("patapim");

pub fn main() !void {
    std.debug.print("All your code belongs to Patapim!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // // ---< Pretty Printing Test >---
    // const source =
    //     \\import "source.brr";
    //     \\import "another.brr" as another;
    //     \\fn hello(arg1, arg2) {}
    //     \\native "C" fn lorem(ipsum: int, dolor);
    //     \\brr x = 1 + 2 * 2 + 4 % 5;
    //     \\const y = [1, 2, ... 3..10];
    //     \\struct Person {
    //     \\    name, age,
    //     \\    fn greet() {
    //     \\      print("Hello, " + this.name + "!");
    //     \\      return this.age;
    //     \\    }
    //     \\}
    //     \\enum E { A, B, C }
    //     \\if (a < b) { print(a); } else if (b < a) { print(b); } else {}
    //     \\loop { print(1); }
    //     \\while (a < b) { print(1); }
    //     \\for(i in 0..5) { print(i); }
    //     \\!a.b().c[1][2];
    //     \\const x = Person { name: "Patapim", age: 321, };
    //     \\const x = #{ name: "Patapim", age: 321, };
    //     \\const y = if (x < z) true else false;
    //     \\y = z;
    // ;

    // // ---< Name Resolution Test >---
    // const source =
    //     \\const x = add(1, 1);
    //     \\const y = Person { age: x };
    //     \\struct Person { age };
    //     \\fn add(a, b) { return a + b; }
    // ;

    // ---< Interpreter Test >---
    const source =
        \\brr abc = 2+2;
        \\brr def = 2*2;
        \\brr ghi = def - abc;
        \\ghi = ghi + (1 * 0.5);
    ;

    var lexer: patapim.Lexer = .{ .source = source };
    var parser = patapim.Parser.init(allocator, &lexer);
    defer parser.deinit(true);

    const module = try parser.parseWholeSource();

    std.debug.print("\n\n---< AST >---\n\n", .{});
    var printer = patapim.ast.PrettyPrinter{
        .writer = std.io.getStdOut().writer().any(),
        .print_spans = false,
    };
    try printer.accept(&parser.tree, module);

    // std.debug.print("\n\n---< Analysis >---\n\n", .{});
    // var metadata = try patapim.analysis.Metadata.init(allocator, &parser.tree);
    // defer metadata.deinit();

    // var item_name_binding_pass = patapim.analysis.ItemNameBindingPass{
    //     .metadata = &metadata,
    // };
    // try item_name_binding_pass.accept(&parser.tree, module);

    // var name_resolution_pass = patapim.analysis.NameResolutionPass{
    //     .metadata = &metadata,
    // };
    // try name_resolution_pass.accept(&parser.tree, module);

    std.debug.print("\n\n---< Interpreter >---\n\n", .{});
    var interpreter = try patapim.Interpreter.init(allocator, &parser.tree);
    defer interpreter.deinit();
    try interpreter.interpret(module);
    try interpreter.printDebugInfo();
}
