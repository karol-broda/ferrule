const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const printer = @import("printer.zig");
const semantic = @import("semantic.zig");
const codegen = @import("codegen.zig");
const diagnostics = @import("diagnostics.zig");
const compilation_context = @import("context.zig");
const logging = @import("logging.zig");

const RUNTIME_LIB_NAME = "libferrule_rt.a";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            // use stderr directly here since logger may already be deinitialized
            std.fs.File.stderr().writeAll("[main] err: memory leak detected\n") catch {};
        }
    }
    const allocator = gpa.allocator();

    // initialize logging from environment or defaults
    var logger = logging.Logger.initWithAllocator(allocator, .warn);
    defer logger.deinit();
    logger.configureFromEnv();

    // parse command line for logging options
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var source_path: ?[]const u8 = null;
    var verbose = false;
    var debug_mode = false;
    var log_scopes: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--log-scopes=")) {
            log_scopes = arg["--log-scopes=".len..];
        } else if (std.mem.startsWith(u8, arg, "--log=")) {
            log_scopes = arg["--log=".len..];
        } else if (arg[0] != '-') {
            source_path = arg;
        }
    }

    // apply command line logging options
    if (debug_mode) {
        logger.default_level = .debug;
    } else if (verbose) {
        logger.default_level = .info;
    }

    if (log_scopes) |scopes| {
        logger.parseConfig(scopes);
    }

    const log = logger.scoped(logging.Scopes.main);

    if (source_path == null) {
        // usage help goes to stdout since it's user-facing cli output
        const stdout = std.fs.File.stdout();
        stdout.writeAll("usage: ferrule [options] <source.fe>\n") catch {};
        stdout.writeAll("\noptions:\n") catch {};
        stdout.writeAll("  -v, --verbose       enable info-level logging\n") catch {};
        stdout.writeAll("  --debug             enable debug-level logging\n") catch {};
        stdout.writeAll("  --log-scopes=SPEC   configure logging scopes (e.g., 'semantic:debug,codegen:trace')\n") catch {};
        stdout.writeAll("\nenvironment:\n") catch {};
        stdout.writeAll("  FERRULE_LOG         same format as --log-scopes\n") catch {};
        return;
    }

    const source_file_path = source_path.?;

    log.info("starting compilation of '{s}'", .{source_file_path});

    const file = std.fs.cwd().openFile(source_file_path, .{}) catch |err| {
        log.err("failed to open file '{s}': {s}", .{ source_file_path, @errorName(err) });
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    // lex
    const lex_log = logger.scoped(logging.Scopes.lexer);
    var lex_span = logger.startSpan(logging.Scopes.lexer, "lexing");
    defer lex_span.end();

    var lex = lexer.Lexer.init(source);
    var tokens: std.ArrayList(lexer.Token) = .empty;
    defer tokens.deinit(allocator);

    while (true) {
        const token = lex.nextToken();
        try tokens.append(allocator, token);
        if (token.type == .eof) break;
    }

    lex_log.debug("lexed {d} tokens", .{tokens.items.len});

    // log tokens at trace level
    const print_count = @min(50, tokens.items.len);
    for (tokens.items[0..print_count]) |token| {
        lex_log.trace("{d:3}:{d:3} {s:15} '{s}'", .{
            token.line,
            token.column,
            @tagName(token.type),
            token.lexeme,
        });
    }

    if (tokens.items.len > 50) {
        lex_log.trace("... and {d} more tokens", .{tokens.items.len - 50});
    }

    // create compilation context early - parser uses scratch arena for AST
    var compilation_ctx = compilation_context.CompilationContext.init(allocator);
    defer compilation_ctx.deinit();

    // parse - use scratch allocator for AST (temporary, freed after semantic analysis if needed)
    const parse_log = logger.scoped(logging.Scopes.parser);
    var parse_span = logger.startSpan(logging.Scopes.parser, "parsing");

    var parse_diagnostics = diagnostics.DiagnosticList.init(allocator);
    defer parse_diagnostics.deinit();
    parse_diagnostics.setSource(source);

    const scratch_alloc = compilation_ctx.scratchAllocator();
    var parse = parser.Parser.initWithDiagnostics(scratch_alloc, tokens.items, &parse_diagnostics, source_file_path);
    const module = parse.parse() catch |err| {
        parse_span.end();
        parse_log.err("parsing failed: {s}", .{@errorName(err)});
        const colors = diagnostics.ColorConfig.init();
        for (parse_diagnostics.diagnostics.items) |diag| {
            var buf = std.ArrayList(u8){};
            defer buf.deinit(allocator);
            diag.formatWithSource(parse_diagnostics.source_content, buf.writer(allocator), colors) catch {};
            parse_log.err("{s}", .{buf.items});
        }
        return err;
    };
    // AST cleanup is handled by scratch arena when ctx.deinit() is called
    parse_span.end();

    parse_log.debug("parsed {d} top-level statements", .{module.statements.len});
    parse_log.info("parsing completed successfully", .{});

    // semantic analysis
    const semantic_log = logger.scoped(logging.Scopes.semantic);
    semantic_log.info("starting semantic analysis", .{});

    var semantic_span = logger.startSpan(logging.Scopes.semantic, "semantic analysis");

    // semantic analysis uses permanent allocator for types
    var analyzer = semantic.SemanticAnalyzer.init(&compilation_ctx, source_file_path, source);
    defer analyzer.deinit();

    // set the logger so semantic passes can log
    analyzer.setLogger(&logger);

    const result = analyzer.analyze(module) catch |err| {
        semantic_span.end();
        semantic_log.err("semantic analysis failed: {s}", .{@errorName(err)});
        return err;
    };
    semantic_span.end();

    if (result.has_errors) {
        semantic_log.err("semantic analysis found errors", .{});
        const colors = diagnostics.ColorConfig.init();
        for (analyzer.diagnostics_list.diagnostics.items) |diag| {
            var buf = std.ArrayList(u8){};
            defer buf.deinit(allocator);
            diag.formatWithSource(analyzer.diagnostics_list.source_content, buf.writer(allocator), colors) catch {};
            semantic_log.err("{s}", .{buf.items});
        }
        std.process.exit(1);
    }

    if (result.typed_module) |typed_module| {
        var mut_typed_module = typed_module;
        defer mut_typed_module.deinit();
        semantic_log.debug("typed {d} statements", .{mut_typed_module.statements.len});
        semantic_log.info("semantic analysis completed successfully", .{});
    }

    // code generation
    const codegen_log = logger.scoped(logging.Scopes.codegen);
    codegen_log.info("starting code generation", .{});

    var codegen_span = logger.startSpan(logging.Scopes.codegen, "code generation");

    // create out directory if it doesn't exist
    std.fs.cwd().makeDir("out") catch |err| {
        if (err != error.PathAlreadyExists) {
            codegen_log.err("failed to create out directory: {s}", .{@errorName(err)});
            return err;
        }
    };

    // extract base filename from source path
    const base_name = blk: {
        const path_sep_idx = if (std.mem.lastIndexOf(u8, source_file_path, "/")) |idx| idx + 1 else 0;
        const name_with_ext = source_file_path[path_sep_idx..];
        if (std.mem.lastIndexOf(u8, name_with_ext, ".fe")) |idx| {
            break :blk name_with_ext[0..idx];
        }
        break :blk name_with_ext;
    };

    const output_base = try std.fmt.allocPrint(allocator, "out/{s}", .{base_name});
    defer allocator.free(output_base);

    codegen.generateFiles(
        &compilation_ctx,
        module,
        &analyzer.symbols,
        &analyzer.diagnostics_list,
        source_file_path,
        source_file_path,
        output_base,
    ) catch |err| {
        codegen_span.end();
        codegen_log.err("code generation failed: {s}", .{@errorName(err)});
        return err;
    };
    codegen_span.end();

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{output_base});
    defer allocator.free(ir_file);
    const asm_file = try std.fmt.allocPrint(allocator, "{s}.s", .{output_base});
    defer allocator.free(asm_file);
    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{output_base});
    defer allocator.free(obj_file);
    const exe_file = output_base;

    codegen_log.info("generated LLVM IR: {s}", .{ir_file});
    codegen_log.info("generated assembly: {s}", .{asm_file});
    codegen_log.info("generated object: {s}", .{obj_file});

    const exe_dir = blk: {
        var self_exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const self_exe_path = std.fs.selfExePath(&self_exe_path_buf) catch {
            break :blk ".";
        };
        const dir_end = std.mem.lastIndexOf(u8, self_exe_path, "/") orelse 0;
        break :blk self_exe_path[0..dir_end];
    };

    const linker_log = logger.scoped(logging.Scopes.linker);
    const runtime_lib_path = try findRuntimeLib(allocator, exe_dir, linker_log);
    defer if (runtime_lib_path) |p| allocator.free(p);

    // linking
    var link_span = logger.startSpan(logging.Scopes.linker, "linking");

    const link_cmd = if (runtime_lib_path) |rt_path|
        try std.fmt.allocPrint(
            allocator,
            "cc {s} {s} -o {s}",
            .{ obj_file, rt_path, exe_file },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "cc {s} -o {s}",
            .{ obj_file, exe_file },
        );
    defer allocator.free(link_cmd);

    linker_log.debug("running link command: {s}", .{link_cmd});

    const link_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-c", link_cmd },
    }) catch |err| {
        link_span.end();
        linker_log.err("failed to run linker: {s}", .{@errorName(err)});
        return err;
    };
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    if (link_result.term.Exited != 0) {
        link_span.end();
        linker_log.err("linker returned non-zero exit code", .{});
        if (link_result.stderr.len > 0) {
            linker_log.err("linker output: {s}", .{link_result.stderr});
        }
        return error.LinkerFailed;
    }
    link_span.end();

    linker_log.info("generated binary: {s}", .{exe_file});
    log.info("compilation complete: {s}", .{exe_file});
}

fn findRuntimeLib(allocator: std.mem.Allocator, exe_dir: []const u8, log: logging.ScopedLogger) !?[]const u8 {
    const search_paths = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ exe_dir, RUNTIME_LIB_NAME }),
        try std.fmt.allocPrint(allocator, "{s}/../lib/{s}", .{ exe_dir, RUNTIME_LIB_NAME }),
        try std.fmt.allocPrint(allocator, "zig-out/lib/{s}", .{RUNTIME_LIB_NAME}),
    };
    defer for (search_paths) |path| {
        allocator.free(path);
    };

    for (search_paths) |path| {
        log.trace("searching for runtime library at: {s}", .{path});
        if (std.fs.cwd().access(path, .{})) |_| {
            log.debug("found runtime library: {s}", .{path});
            return try allocator.dupe(u8, path);
        } else |_| {
            continue;
        }
    }

    log.warn("runtime library not found, io functions will not work", .{});
    return null;
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
