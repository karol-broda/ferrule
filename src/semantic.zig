const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const symbol_table = @import("symbol_table.zig");
const error_domains = @import("error_domains.zig");
const diagnostics = @import("diagnostics.zig");
const typed_ast = @import("typed_ast.zig");
const hover_info = @import("hover_info.zig");
const symbol_locations = @import("symbol_locations.zig");

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

    pub fn init(allocator: std.mem.Allocator, source_file: []const u8, source_content: []const u8) SemanticAnalyzer {
        var diag_list = diagnostics.DiagnosticList.init(allocator);
        diag_list.setSourceContent(source_content);
        return .{
            .allocator = allocator,
            .symbols = symbol_table.SymbolTable.init(allocator),
            .domains = error_domains.ErrorDomainTable.init(allocator),
            .diagnostics_list = diag_list,
            .source_file = source_file,
            .hover_table = hover_info.HoverInfoTable.init(allocator),
            .location_table = symbol_locations.SymbolLocationTable.init(allocator),
        };
    }

    pub fn deinit(self: *SemanticAnalyzer) void {
        self.symbols.deinit();
        self.domains.deinit();
        self.diagnostics_list.deinit();
        self.hover_table.deinit();
        self.location_table.deinit();
    }

    pub fn analyze(self: *SemanticAnalyzer, module: ast.Module) !AnalysisResult {
        try self.runPass1CollectDeclarations(module);
        // stop if declarations failed since later passes need them
        if (self.diagnostics_list.hasErrors()) {
            return AnalysisResult{
                .typed_module = null,
                .has_errors = true,
            };
        }

        // continue through all remaining passes to collect all errors
        try self.runPass2ResolveTypes(module);
        const typed_module = try self.runPass3TypeCheck(module);
        try self.runPass4EffectCheck(module);
        try self.runPass5ErrorCheck(module);
        try self.runPass6RegionCheck(module);
        try self.runPass7ExhaustivenessCheck(module);

        return AnalysisResult{
            .typed_module = typed_module,
            .has_errors = self.diagnostics_list.hasErrors(),
        };
    }

    fn runPass1CollectDeclarations(self: *SemanticAnalyzer, module: ast.Module) !void {
        var collector = DeclarationCollector.init(
            self.allocator,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
            &self.location_table,
        );
        try collector.collect(module);
    }

    fn runPass2ResolveTypes(self: *SemanticAnalyzer, module: ast.Module) !void {
        var resolver = TypeResolver.init(
            self.allocator,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );

        var iter = self.symbols.global_scope.symbols.iterator();
        while (iter.next()) |entry| {
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

                    for (original_func_decl.params, 0..) |param, i| {
                        func.params[i] = try resolver.resolve(param.type_annotation);
                    }

                    func.return_type = try resolver.resolve(original_func_decl.return_type);
                },
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

                    type_def.underlying = try resolver.resolve(original_type_decl.type_expr);

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

            try self.symbols.global_scope.symbols.put(entry.key_ptr.*, symbol);
        }

        for (module.statements) |stmt| {
            if (stmt == .domain_decl) {
                const domain_decl = stmt.domain_decl;
                var variant_infos = try self.allocator.alloc(hover_info.DomainVariantInfo, domain_decl.variants.len);
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

                for (domain_decl.variants, 0..) |variant, i| {
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

    fn runPass3TypeCheck(self: *SemanticAnalyzer, module: ast.Module) !?typed_ast.TypedModule {
        var checker = TypeChecker.init(
            self.allocator,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
            &self.hover_table,
            &self.location_table,
        );

        return try checker.checkModule(module);
    }

    fn runPass4EffectCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        var checker = EffectChecker.init(
            self.allocator,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
    }

    fn runPass5ErrorCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        var checker = ErrorChecker.init(
            self.allocator,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
    }

    fn runPass6RegionCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        var checker = RegionChecker.init(
            self.allocator,
            &self.symbols,
            &self.diagnostics_list,
            self.source_file,
        );
        defer checker.deinit();

        try checker.checkModule(module);
    }

    fn runPass7ExhaustivenessCheck(self: *SemanticAnalyzer, module: ast.Module) !void {
        var checker = ExhaustivenessChecker.init(
            self.allocator,
            &self.symbols,
            &self.domains,
            &self.diagnostics_list,
            self.source_file,
        );

        try checker.checkModule(module);
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
