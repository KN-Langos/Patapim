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
        \\brr x = 1 + 2 * 2 + 4 % 5;
        \\const y = [1, 2, ... 3..10];
        \\struct Person {
        \\    name, age,
        \\    fn greet() { 
        \\      print("Hello, " + this.name + "!"); 
        \\      return this.age;
        \\    }
        \\}
        \\enum E { A, B, C }
        \\if (a < b) { print(a); } else if (b < a) { print(b); } else {}
        \\loop { print(1); break; }
        \\while (a < b) { print(1); continue; }
        \\for(i in 0..5) { print(i); }
        \\!a.b().c[1][2];
        \\const x = Person { name: "Patapim", age: 321, };
        \\const x = #{ name: "Patapim", age: 321, };
        \\const y = if (x < z) true else false;
        \\y = z;
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
