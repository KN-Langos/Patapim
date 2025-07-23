const std = @import("std");

const zli = @import("zli");

pub fn build(allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(allocator, .{
        .name = "patapim",
        .description = "Interpreter for Patapim programming language.",
        .version = comptime try std.SemanticVersion.parse("1.0.0-prealpha"),
    }, showHelp);

    try root.addCommands(&.{
        try @import("run_cmd.zig").register(allocator),
    });

    return root;
}

fn showHelp(cx: zli.CommandContext) !void {
    try cx.command.printHelp();
}
