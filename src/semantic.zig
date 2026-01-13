const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const symbol_table = @import("symbol_table.zig");
const error_domains = @import("error_domains.zig");
const diagnostics = @import("diagnostics.zig");
const typed_ast = @import("typed_ast.zig");
const hover_info = @import("hover_info.zig");
const symbol_locations = @import("symbol_locations.zig");
const context = @import("context.zig");
const logging = @import("logging.zig");

const DeclarationCollector = @import("semantic/declaration_pass.zig").DeclarationCollector;
const TypeResolver = @import("semantic/type_resolver.zig").TypeResolver;
const TypeChecker = @import("semantic/type_checker.zig").TypeChecker;
const EffectChecker = @import("semantic/effect_checker.zig").EffectChecker;
const ErrorChecker = @import("semantic/error_checker.zig").ErrorChecker;
const RegionChecker = @import("semantic/region_checker.zig").RegionChecker;
const ExhaustivenessChecker = @import("semantic/exhaustiveness.zig").ExhaustivenessChecker;

pub const SemanticAnalyzer = struct {
    allocator: std.mem.Allocator,
    symbols: symbol_table.SymbolTable,
    domains: error_domains.ErrorDomainTable,
    diagnostics_list: diagnostics.DiagnosticList,
    source_file: []const u8,
    hover_table: hover_info.HoverInfoTable,
    location_table: symbol_locations.SymbolLocationTable,

    // compilation context for arena-based memory management and interning
    // types and strings are interned for deduplication and simplified cleanup
    compilation_context: *context.CompilationContext,

    // optional logger for debugging and tracing
    logger: ?*const logging.Logger,

    // creates a semantic analyzer with a compilation context
    // types and strings will be interned in the context's permanent arena
    pub fn init(ctx: *context.CompilationContext, source_file: []const u8, source_content: []const u8) SemanticAnalyzer {
        const allocator = ctx.permanentAllocator();
        var diag_list = diagnostics.DiagnosticList.init(allocator);
        diag_list.setSourceContent(source_content);
        return .{
            .allocator = allocator,
            .symbols = symbol_table.SymbolTable.init(ctx),
            .domains = error_domains.ErrorDomainTable.init(ctx),
            .diagnostics_list = diag_list,
            .source_file = source_file,
            .hover_table = hover_info.HoverInfoTable.init(ctx),
            .location_table = symbol_locations.SymbolLocationTable.init(ctx),
            .compilation_context = ctx,
            .logger = null,
        };
    }

    // sets the logger for this analyzer and sub-passes
    pub fn setLogger(self: *SemanticAnalyzer, log: *const logging.Logger) void {
        self.logger = log;
    }

    // creates a scoped logger for a specific pass
    fn scopedLogger(self: *const SemanticAnalyzer, scope: []const u8) logging.ScopedLogger {
        if (self.logger) |log| {
            return log.scoped(scope);
        }
        // use static disabled logger to avoid dangling pointer
        return logging.disabled_logger.scoped(scope);
    }

    pub fn deinit(self: *SemanticAnalyzer) void {
        // arena cleanup handles everything when context owner calls ctx.deinit()
        // only hashmap structures require explicit cleanup
        self.symbols.deinit();
        self.domains.deinit();
        self.hover_table.deinit();
        self.location_table.deinit();
    }

    // interns a string in the context's arena
    pub fn internString(self: *SemanticAnalyzer, str: []const u8) ![]const u8 {
        return self.compilation_context.internString(str);
    }

    // interns a type in the context's arena
    pub fn internType(self: *SemanticAnalyzer, resolved_type: types.ResolvedType) !*const types.ResolvedType {
        return self.compilation_context.internType(resolved_type);
    }

    pub fn analyze(self: *SemanticAnalyzer, module: ast.Module) !AnalysisResult {
        const log = self.scopedLogger(logging.Scopes.semantic);

        log.info("starting semantic analysis", .{});
        log.debug("module has {d} top-level statements", .{module.statements.len});

        try self.runPass1CollectDeclarations(module);
        // stop if declarations failed since later passes need them
        if (self.diagnostics_list.hasErrors()) {
            log.warn("pass 1 (declarations) failed with errors, stopping analysis", .{});
            return AnalysisResult{
                .typed_module = null,
                .has_errors = true,
            };
        }
        log.debug("pass 1 (declarations) completed", .{});

        // continue through all remaining passes to collect all errors
        try self.runPass2ResolveTypes(module);
        log.debug("pass 2 (type resolution) completed", .{});

        const typed_module = try self.runPass3TypeCheck(module);
        log.debug("pass 3 (type checking) completed", .{});

        try self.runPass4EffectCheck(module);
        log.debug("pass 4 (effect checking) completed", .{});

        try self.runPass5ErrorCheck(module);
        log.debug("pass 5 (error checking) completed", .{});

        try self.runPass6RegionCheck(module);
        log.debug("pass 6 (region checking) completed", .{});

        try self.runPass7ExhaustivenessCheck(module);
        log.debug("pass 7 (exhaustiveness checking) completed", .{});

        const has_errors = self.diagnostics_list.hasErrors();
        if (has_errors) {
            log.warn("semantic analysis completed with errors", .{});
        } else {
            log.info("semantic analysis completed successfully", .{});
        }

        return AnalysisResult{
            .typed_module = typed_module,
            .has_errors = has_errors,
        };
    }

    fn runPass1CollectDeclarations(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_declarations);
        log.trace("starting declaration collection", .{});

        var collector = DeclarationCollector.init(
            self.compilation_context,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
            &self.location_table,
        );

        try collector.collect(module);

        log.trace("declaration collection finished", .{});
    }

    fn runPass2ResolveTypes(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_type_resolver);
        log.trace("starting type resolution", .{});

        var resolver = TypeResolver.init(
            self.compilation_context,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );

        // first pass: resolve all type definitions
        // this must happen before functions so that parameter types can reference them
        var type_iter = self.symbols.global_scope.symbols.iterator();
        while (type_iter.next()) |entry| {
            var symbol = entry.value_ptr.*;
            switch (symbol) {
                .type_def => |*type_def| {
                    const original_type_decl = blk: {
                        for (module.statements) |stmt| {
                            if (stmt == .type_decl) {
                                if (std.mem.eql(u8, stmt.type_decl.name, type_def.name)) {
                                    break :blk stmt.type_decl;
                                }
                            }
                        }
                        continue;
                    };

                    log.trace("resolving type definition '{s}'", .{type_def.name});

                    // set up type parameter context for generic types
                    if (original_type_decl.type_params) |tps| {
                        const names = try self.allocator.alloc([]const u8, tps.len);
                        const is_const = try self.allocator.alloc(bool, tps.len);
                        for (tps, 0..) |tp, i| {
                            names[i] = tp.name;
                            is_const[i] = tp.is_const;
                        }
                        resolver.setTypeParamContext(.{
                            .type_param_names = names,
                            .is_const = is_const,
                        });
                    }

                    type_def.underlying = try resolver.resolve(original_type_decl.type_expr);

                    // write modified symbol back to symbol table
                    entry.value_ptr.* = symbol;

                    // clear type param context
                    if (original_type_decl.type_params) |tps| {
                        self.allocator.free(resolver.type_param_context.type_param_names);
                        self.allocator.free(resolver.type_param_context.is_const);
                        _ = tps;
                    }
                    resolver.clearTypeParamContext();

                    try self.hover_table.add(
                        original_type_decl.name_loc.line,
                        original_type_decl.name_loc.column,
                        original_type_decl.name.len,
                        original_type_decl.name,
                        .type_def,
                        type_def.underlying,
                    );
                },
                else => {},
            }
        }

        // second pass: resolve all function declarations
        // now that type definitions are resolved, parameter types will be correct
        var func_iter = self.symbols.global_scope.symbols.iterator();
        while (func_iter.next()) |entry| {
            var symbol = entry.value_ptr.*;
            switch (symbol) {
                .function => |*func| {
                    const original_func_decl = blk: {
                        for (module.statements) |stmt| {
                            if (stmt == .function_decl) {
                                if (std.mem.eql(u8, stmt.function_decl.name, func.name)) {
                                    break :blk stmt.function_decl;
                                }
                            }
                        }
                        continue;
                    };

                    log.trace("resolving function '{s}' parameters and return type", .{func.name});

                    // set up type parameter context for generic functions
                    if (original_func_decl.type_params) |tps| {
                        const names = try self.allocator.alloc([]const u8, tps.len);
                        const is_const = try self.allocator.alloc(bool, tps.len);
                        for (tps, 0..) |tp, i| {
                            names[i] = tp.name;
                            is_const[i] = tp.is_const;
                        }
                        resolver.setTypeParamContext(.{
                            .type_param_names = names,
                            .is_const = is_const,
                        });
                    }

                    for (original_func_decl.params, 0..) |param, i| {
                        func.params[i] = try resolver.resolve(param.type_annotation);
                    }

                    func.return_type = try resolver.resolve(original_func_decl.return_type);

                    // clear type param context
                    if (original_func_decl.type_params) |tps| {
                        self.allocator.free(resolver.type_param_context.type_param_names);
                        self.allocator.free(resolver.type_param_context.is_const);
                        _ = tps;
                    }
                    resolver.clearTypeParamContext();
                    // write modified symbol back to symbol table
                    entry.value_ptr.* = symbol;
                },
                else => {},
            }
        }

        for (module.statements) |stmt| {
            if (stmt == .domain_decl) {
                const domain_decl = stmt.domain_decl;

                log.trace("resolving domain '{s}'", .{domain_decl.name});

                // handle union syntax (error_union) - just store error names as variants
                if (domain_decl.error_union) |error_names| {
                    var variant_infos = try self.allocator.alloc(hover_info.DomainVariantInfo, error_names.len);
                    errdefer self.allocator.free(variant_infos);

                    for (error_names, 0..) |err_name, i| {
                        variant_infos[i] = .{
                            .name = err_name,
                            .field_names = &[_][]const u8{},
                            .field_types = &[_]types.ResolvedType{},
                        };
                    }

                    try self.hover_table.addDomain(
                        domain_decl.name_loc.line,
                        domain_decl.name_loc.column,
                        domain_decl.name.len,
                        domain_decl.name,
                        variant_infos,
                    );

                    self.allocator.free(variant_infos);
                } else if (domain_decl.variants) |variants| {
                    // handle inline variant syntax
                    var variant_infos = try self.allocator.alloc(hover_info.DomainVariantInfo, variants.len);
                    errdefer self.allocator.free(variant_infos);

                    // track all temp allocations for cleanup
                    var temp_field_names = std.ArrayList([][]const u8){};
                    defer {
                        for (temp_field_names.items) |names| {
                            self.allocator.free(names);
                        }
                        temp_field_names.deinit(self.allocator);
                    }
                    var temp_field_types = std.ArrayList([]types.ResolvedType){};
                    defer {
                        for (temp_field_types.items) |type_arr| {
                            self.allocator.free(type_arr);
                        }
                        temp_field_types.deinit(self.allocator);
                    }

                    for (variants, 0..) |variant, i| {
                        const field_names = try self.allocator.alloc([]const u8, variant.fields.len);
                        try temp_field_names.append(self.allocator, field_names);
                        const field_types = try self.allocator.alloc(types.ResolvedType, variant.fields.len);
                        try temp_field_types.append(self.allocator, field_types);

                        for (variant.fields, 0..) |field, j| {
                            field_names[j] = field.name;
                            field_types[j] = try resolver.resolve(field.type_annotation);
                        }

                        variant_infos[i] = .{
                            .name = variant.name,
                            .field_names = field_names,
                            .field_types = field_types,
                        };
                    }

                    try self.hover_table.addDomain(
                        domain_decl.name_loc.line,
                        domain_decl.name_loc.column,
                        domain_decl.name.len,
                        domain_decl.name,
                        variant_infos,
                    );

                    self.allocator.free(variant_infos);
                }
            }
        }

        log.trace("type resolution finished", .{});
    }

    fn runPass3TypeCheck(self: *SemanticAnalyzer, module: ast.Module) !?typed_ast.TypedModule {
        const log = self.scopedLogger(logging.Scopes.semantic_type_checker);
        log.trace("starting type checking", .{});

        var checker = TypeChecker.init(
            self.compilation_context,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
            &self.hover_table,
            &self.location_table,
        );

        checker.setDomainTable(&self.domains);

        const result = try checker.checkModule(module);
        log.trace("type checking finished", .{});
        return result;
    }

    fn runPass4EffectCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_effects);
        log.trace("starting effect checking", .{});

        var checker = EffectChecker.init(
            self.compilation_context,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
        log.trace("effect checking finished", .{});
    }

    fn runPass5ErrorCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_errors);
        log.trace("starting error domain checking", .{});

        var checker = ErrorChecker.init(
            self.compilation_context,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
        log.trace("error domain checking finished", .{});
    }

    fn runPass6RegionCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_regions);
        log.trace("starting region checking", .{});

        var checker = RegionChecker.init(
            self.compilation_context,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );
        defer checker.deinit();

        try checker.checkModule(module);
        log.trace("region checking finished", .{});
    }

    fn runPass7ExhaustivenessCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        const log = self.scopedLogger(logging.Scopes.semantic_exhaustiveness);
        log.trace("starting exhaustiveness checking", .{});

        var checker = ExhaustivenessChecker.init(
            self.compilation_context,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
        log.trace("exhaustiveness checking finished", .{});
    }

    pub fn printDiagnostics(self: *const SemanticAnalyzer, writer: anytype) !void {
        try self.diagnostics_list.print(writer);
    }

    pub fn printDiagnosticsDebug(self: *const SemanticAnalyzer) void {
        const stderr = std.debug;
        const colors = diagnostics.ColorConfig.init();
        for (self.diagnostics_list.diagnostics.items) |diag| {
            var buf = std.ArrayList(u8){};
            defer buf.deinit(self.allocator);
            diag.formatWithSource(self.diagnostics_list.source_content, buf.writer(self.allocator), colors) catch {};
            stderr.print("{s}\n", .{buf.items});
        }
    }
};

pub const AnalysisResult = struct {
    typed_module: ?typed_ast.TypedModule,
    has_errors: bool,
};
