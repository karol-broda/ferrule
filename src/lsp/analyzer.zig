const std = @import("std");

const ferrule = @import("ferrule");
const lexer = ferrule.lexer;
const parser = ferrule.parser;
const semantic = ferrule.semantic;
const diagnostics = ferrule.diagnostics;
const hover_info = ferrule.hover_info;
const symbol_locations = ferrule.symbol_locations;
const context = ferrule.context;

const DocumentState = @import("document.zig").DocumentState;

// result of document analysis
pub const AnalysisResult = struct {
    diagnostics: []const diagnostics.Diagnostic,
    hover_table: ?hover_info.HoverInfoTable,
    location_table: ?symbol_locations.SymbolLocationTable,
    // compilation context that owns all the interned data
    // caller must keep this alive as long as hover_table and location_table are used
    compilation_context: ?*context.CompilationContext,
};

pub fn analyzeDocument(
    allocator: std.mem.Allocator,
    uri: []const u8,
    source: []const u8,
) AnalysisResult {
    // create compilation context for arena-based memory management
    const ctx_ptr = allocator.create(context.CompilationContext) catch {
        return .{
            .diagnostics = &[_]diagnostics.Diagnostic{},
            .hover_table = null,
            .location_table = null,
            .compilation_context = null,
        };
    };
    ctx_ptr.* = context.CompilationContext.init(allocator);

    // create diagnostics list for parse errors
    var parse_diags = diagnostics.DiagnosticList.init(allocator);

    // lex
    var lex = lexer.Lexer.init(source);
    var tokens = std.ArrayList(lexer.Token){};
    defer tokens.deinit(allocator);

    while (true) {
        const token = lex.nextToken();
        tokens.append(allocator, token) catch {
            ctx_ptr.deinit();
            allocator.destroy(ctx_ptr);
            return .{
                .diagnostics = &[_]diagnostics.Diagnostic{},
                .hover_table = null,
                .location_table = null,
                .compilation_context = null,
            };
        };
        if (token.type == .eof) break;
    }

    // parse - use scratch allocator for AST (temporary, freed with context)
    const scratch_alloc = ctx_ptr.scratchAllocator();
    var parse = parser.Parser.initWithDiagnostics(scratch_alloc, tokens.items, &parse_diags, uri);
    const module = parse.parse() catch {
        return .{
            .diagnostics = parse_diags.diagnostics.items,
            .hover_table = null,
            .location_table = null,
            .compilation_context = ctx_ptr,
        };
    };
    // AST cleanup is handled by scratch arena when ctx.deinit() is called

    // semantic analysis using context for interned types and strings
    var analyzer = semantic.SemanticAnalyzer.init(ctx_ptr, uri, source);

    _ = analyzer.analyze(module) catch {
        return .{
            .diagnostics = analyzer.diagnostics_list.diagnostics.items,
            .hover_table = analyzer.hover_table,
            .location_table = analyzer.location_table,
            .compilation_context = ctx_ptr,
        };
    };

    return .{
        .diagnostics = analyzer.diagnostics_list.diagnostics.items,
        .hover_table = analyzer.hover_table,
        .location_table = analyzer.location_table,
        .compilation_context = ctx_ptr,
    };
}

// updates document state with analysis results
pub fn updateDocumentWithAnalysis(doc: *DocumentState, result: *AnalysisResult, allocator: std.mem.Allocator) void {
    // free old compilation context
    doc.hover_table.deinit();
    doc.location_table.deinit();
    doc.compilation_context.deinit();
    allocator.destroy(doc.compilation_context);

    if (result.hover_table) |*table| {
        doc.hover_table = table.*;
        result.hover_table = null;
    }

    if (result.location_table) |*table| {
        doc.location_table = table.*;
        result.location_table = null;
    }

    // transfer ownership of compilation context to document
    if (result.compilation_context) |ctx| {
        doc.compilation_context = ctx;
        result.compilation_context = null;
    }
}
