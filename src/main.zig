const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const printer = @import("printer.zig");
const semantic = @import("semantic.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("usage: ferrule <source.fe>\n", .{});
        return;
    }

    const source_path = args[1];

    const file = std.fs.cwd().openFile(source_path, .{}) catch |err| {
        std.debug.print("error opening file '{s}': {s}\n", .{ source_path, @errorName(err) });
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    std.debug.print("=== compiling {s} ===\n\n", .{source_path});

    // lex
    var lex = lexer.Lexer.init(source);
    var tokens: std.ArrayList(lexer.Token) = .empty;
    defer tokens.deinit(allocator);

    while (true) {
        const token = lex.nextToken();
        try tokens.append(allocator, token);
        if (token.type == .eof) break;
    }

    std.debug.print("lexed {d} tokens:\n", .{tokens.items.len});

    // print first 50 tokens or all if less
    const print_count = @min(50, tokens.items.len);
    for (tokens.items[0..print_count]) |token| {
        std.debug.print("  {d:3}:{d:3} {s:15} '{s}'\n", .{
            token.line,
            token.column,
            @tagName(token.type),
            token.lexeme,
        });
    }

    if (tokens.items.len > 50) {
        std.debug.print("  ... and {d} more tokens\n", .{tokens.items.len - 50});
    }

    std.debug.print("\n", .{});

    // parse
    var parse = parser.Parser.init(allocator, tokens.items);
    const module = parse.parse() catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer module.deinit(allocator);

    std.debug.print("parsed successfully\n\n", .{});

    // semantic analysis
    std.debug.print("=== semantic analysis ===\n\n", .{});
    var analyzer = semantic.SemanticAnalyzer.init(allocator, source_path, source);
    defer analyzer.deinit();

    const result = analyzer.analyze(module) catch |err| {
        std.debug.print("semantic analysis error: {s}\n", .{@errorName(err)});
        return err;
    };

    if (result.has_errors) {
        std.debug.print("\n=== semantic errors ===\n\n", .{});
        analyzer.printDiagnosticsDebug();
        std.debug.print("\n=== compilation failed ===\n", .{});
        std.process.exit(1);
    }

    if (result.typed_module) |typed_module| {
        var mut_typed_module = typed_module;
        defer mut_typed_module.deinit();
        std.debug.print("semantic analysis completed: {d} statements typed\n\n", .{mut_typed_module.statements.len});
    }

    std.debug.print("=== compilation complete ===\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
