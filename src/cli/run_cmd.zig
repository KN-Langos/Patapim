const std = @import("std");

const patapim = @import("patapim");
const reportz = @import("reportz");
const zli = @import("zli");

const debug_ast_flag = zli.Flag{
    .name = "debug-ast",
    .shortcut = "da",
    .description = "Print AST for debugging",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const debug_interpreter = zli.Flag{
    .name = "debug-interpreter",
    .shortcut = "di",
    .description = "Print debug info from interpreter",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

pub fn register(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "run",
        .description = "Run a given patapim file",
    }, runFile);

    try cmd.addFlag(debug_ast_flag);
    try cmd.addFlag(debug_interpreter);
    try cmd.addPositionalArg(.{
        .name = "script",
        .description = "Patapim source file to execute",
        .required = true,
    });

    return cmd;
}

fn runFile(cx: zli.CommandContext) !void {
    const source_path = cx.getArg("script") orelse unreachable;
    const cwd = std.fs.cwd();

    const source_file = try cwd.openFile(source_path, .{ .mode = .read_only });
    defer source_file.close();

    const source = try source_file.readToEndAlloc(cx.allocator, 10_000);
    defer cx.allocator.free(source);

    var lexer: patapim.Lexer = .{
        .source = source,
        .source_id = source_path,
    };
    var parser: patapim.Parser = .init(cx.allocator, &lexer);
    defer parser.deinit(true);

    var reportz_cache: reportz.cache.SourceCache = .init(cx.allocator);
    defer reportz_cache.deinit();
    try reportz_cache.addSource(source_path, source);

    // Parse provided source.
    const module = parser.parseWholeSource() catch |err| return reportErrors(
        err,
        cx.allocator,
        &reportz_cache,
        parser.diagnostic_log.items,
    );

    // Possibly print debug AST.
    if (cx.flag("debug-ast", bool)) {
        var pretty_printer = patapim.ast.PrettyPrinter{
            .writer = std.io.getStdOut().writer().any(),
            .print_spans = false,
        };
        try pretty_printer.accept(&parser.tree, module);
    }

    // Analysis.
    var metadata: patapim.analysis.Metadata = try .init(cx.allocator, &parser.tree);
    defer metadata.deinit();

    var item_name_binding_pass: patapim.analysis.ItemNameBindingPass = .{
        .metadata = &metadata,
    };
    // This can only fail if allocator fails.
    try item_name_binding_pass.accept(&parser.tree, module);

    var error_arena = std.heap.ArenaAllocator.init(cx.allocator);
    defer error_arena.deinit();

    var name_resolution_pass: patapim.analysis.NameResolutionPass = .{
        .source_id = lexer.source_id,
        .metadata = &metadata,
        .diagnostic_alloc = error_arena.allocator(),
        .diagnostic_log = .init(error_arena.allocator()),
    };
    name_resolution_pass.accept(&parser.tree, module) catch |err| return reportErrors(
        err,
        cx.allocator,
        &reportz_cache,
        name_resolution_pass.diagnostic_log.items,
    );

    // Run the source!
    var interpreter: patapim.Interpreter = try .init(
        cx.allocator,
        &parser.tree,
        lexer.source_id,
    );
    defer interpreter.deinit();

    interpreter.interpret(module) catch |err| return reportErrors(
        err,
        cx.allocator,
        &reportz_cache,
        interpreter.diagnostic_log.items,
    );

    if (cx.flag("debug-interpreter", bool))
        try interpreter.printDebugInfo();
}

fn reportErrors(
    err: anyerror,
    allocator: std.mem.Allocator,
    cache: *reportz.cache.SourceCache,
    log: []const reportz.reports.Diagnostic,
) anyerror {
    var stderr_writer = std.io.getStdErr().writer().any();
    var renderer = reportz.Renderer{
        .allocator = allocator,
        .writer = &stderr_writer,
        .source_cache = cache,
    };

    for (log) |*diag|
        try renderer.render(diag);

    return err;
}
