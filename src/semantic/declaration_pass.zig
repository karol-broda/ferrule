const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");
const symbol_locations = @import("../symbol_locations.zig");

pub const DeclarationCollector = struct {
    symbols: *symbol_table.SymbolTable,
    domains: *error_domains.ErrorDomainTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    location_table: *symbol_locations.SymbolLocationTable,

    pub fn init(
        allocator: std.mem.Allocator,
        symbols: *symbol_table.SymbolTable,
        domains: *error_domains.ErrorDomainTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
        location_table: *symbol_locations.SymbolLocationTable,
    ) DeclarationCollector {
        return .{
            .symbols = symbols,
            .domains = domains,
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
            .location_table = location_table,
        };
    }

    pub fn collect(self: *DeclarationCollector, module: ast.Module) !void {
        for (module.statements) |stmt| {
            try self.collectStatement(stmt);
        }
    }

    fn collectStatement(self: *DeclarationCollector, stmt: ast.Stmt) !void {
        switch (stmt) {
            .function_decl => |fd| try self.collectFunction(fd),
            .type_decl => |td| try self.collectTypeDecl(td),
            .error_decl => |ed| try self.collectErrorDecl(ed),
            .domain_decl => |dd| try self.collectDomain(dd),
            .const_decl => |cd| try self.collectConst(cd),
            else => {},
        }
    }

    pub fn collectFunction(self: *DeclarationCollector, func: ast.FunctionDecl) !void {
        if (self.symbols.lookupGlobal(func.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of function '{s}'",
                    .{func.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = func.name.len,
                },
                null,
            );
            return;
        }

        const params = try self.allocator.alloc(@import("../types.zig").ResolvedType, func.params.len);
        errdefer self.allocator.free(params);

        const param_names = try self.allocator.alloc([]const u8, func.params.len);
        errdefer self.allocator.free(param_names);

        const is_capability = try self.allocator.alloc(bool, func.params.len);
        errdefer self.allocator.free(is_capability);

        for (func.params, 0..) |param, i| {
            is_capability[i] = param.is_capability;
            params[i] = .unit_type;
            param_names[i] = param.name;
        }

        const effects = try self.allocator.alloc(@import("../types.zig").Effect, func.effects.len);
        errdefer self.allocator.free(effects);

        for (func.effects, 0..) |effect_str, i| {
            if (@import("../types.zig").Effect.fromString(effect_str)) |effect| {
                effects[i] = effect;
            } else {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "unknown effect '{s}'",
                        .{effect_str},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = effect_str.len,
                    },
                    null,
                );
                self.allocator.free(effects);
                self.allocator.free(is_capability);
                self.allocator.free(param_names);
                self.allocator.free(params);
                return;
            }
        }

        // collect type parameters if present
        const type_params: ?[]types.TypeParamInfo = if (func.type_params) |tps| blk: {
            const tp_infos = try self.allocator.alloc(types.TypeParamInfo, tps.len);
            for (tps, 0..) |tp, i| {
                tp_infos[i] = .{
                    .name = try self.allocator.dupe(u8, tp.name),
                    .variance = switch (tp.variance) {
                        .invariant => .invariant,
                        .covariant => .covariant,
                        .contravariant => .contravariant,
                    },
                    .constraint = null,
                    .is_const = tp.is_const,
                    .const_type = null,
                };
            }
            break :blk tp_infos;
        } else null;

        const symbol = symbol_table.Symbol{
            .function = .{
                .name = func.name,
                .type_params = type_params,
                .params = params,
                .param_names = param_names,
                .return_type = .unit_type,
                .effects = effects,
                .error_domain = func.error_domain,
                .is_capability_param = is_capability,
            },
        };

        try self.symbols.insertGlobal(func.name, symbol);

        try self.location_table.addDefinition(
            func.name,
            func.name_loc.line,
            func.name_loc.column,
            func.name.len,
        );
    }

    pub fn collectTypeDecl(self: *DeclarationCollector, type_decl: ast.TypeDecl) !void {
        if (self.symbols.lookupGlobal(type_decl.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of type '{s}'",
                    .{type_decl.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = type_decl.name.len,
                },
                null,
            );
            return;
        }

        // collect type parameters if present
        const type_params: ?[]types.TypeParamInfo = if (type_decl.type_params) |tps| blk: {
            const tp_infos = try self.allocator.alloc(types.TypeParamInfo, tps.len);
            for (tps, 0..) |tp, i| {
                tp_infos[i] = .{
                    .name = try self.allocator.dupe(u8, tp.name),
                    .variance = switch (tp.variance) {
                        .invariant => .invariant,
                        .covariant => .covariant,
                        .contravariant => .contravariant,
                    },
                    .constraint = null,
                    .is_const = tp.is_const,
                    .const_type = null,
                };
            }
            break :blk tp_infos;
        } else null;

        const symbol = symbol_table.Symbol{
            .type_def = .{
                .name = type_decl.name,
                .type_params = type_params,
                .underlying = .unit_type,
            },
        };

        try self.symbols.insertGlobal(type_decl.name, symbol);

        try self.location_table.addDefinition(
            type_decl.name,
            type_decl.name_loc.line,
            type_decl.name_loc.column,
            type_decl.name.len,
        );
    }

    pub fn collectErrorDecl(self: *DeclarationCollector, error_decl: ast.ErrorDecl) !void {
        if (self.symbols.lookupGlobal(error_decl.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of error '{s}'",
                    .{error_decl.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = error_decl.name.len,
                },
                null,
            );
            return;
        }

        const symbol = symbol_table.Symbol{
            .error_type = .{
                .name = error_decl.name,
            },
        };

        try self.symbols.insertGlobal(error_decl.name, symbol);

        try self.location_table.addDefinition(
            error_decl.name,
            error_decl.name_loc.line,
            error_decl.name_loc.column,
            error_decl.name.len,
        );
    }

    pub fn collectDomain(self: *DeclarationCollector, domain: ast.DomainDecl) !void {
        if (self.symbols.lookupGlobal(domain.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of domain '{s}'",
                    .{domain.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = domain.name.len,
                },
                null,
            );
            return;
        }

        const symbol = symbol_table.Symbol{
            .domain = .{
                .name = domain.name,
            },
        };

        try self.symbols.insertGlobal(domain.name, symbol);

        // Handle both union syntax (error_union) and inline variant syntax (variants)
        if (domain.error_union) |error_names| {
            // Union syntax: domain IoError = NotFound | Denied;
            const variants = try self.allocator.alloc(error_domains.ErrorVariant, error_names.len);
            for (error_names, 0..) |err_name, i| {
                variants[i] = .{
                    .name = err_name,
                    .fields = &[_]error_domains.Field{},
                };
            }

            const error_domain = error_domains.ErrorDomain{
                .name = domain.name,
                .variants = variants,
            };

            try self.domains.insert(domain.name, error_domain);
        } else if (domain.variants) |inline_variants| {
            // Inline variant syntax: domain IoError { NotFound { path: String } }
            const variants = try self.allocator.alloc(error_domains.ErrorVariant, inline_variants.len);
            for (inline_variants, 0..) |variant, i| {
                variants[i] = .{
                    .name = variant.name,
                    .fields = &[_]error_domains.Field{},
                };
            }

            const error_domain = error_domains.ErrorDomain{
                .name = domain.name,
                .variants = variants,
            };

            try self.domains.insert(domain.name, error_domain);
        }

        try self.location_table.addDefinition(
            domain.name,
            domain.name_loc.line,
            domain.name_loc.column,
            domain.name.len,
        );
    }

    pub fn collectConst(self: *DeclarationCollector, const_decl: ast.ConstDecl) !void {
        if (self.symbols.lookupGlobal(const_decl.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of constant '{s}'",
                    .{const_decl.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = const_decl.name.len,
                },
                null,
            );
            return;
        }

        const symbol = symbol_table.Symbol{
            .constant = .{
                .name = const_decl.name,
                .type_annotation = .unit_type,
                .scope_level = 0,
            },
        };

        try self.symbols.insertGlobal(const_decl.name, symbol);

        try self.location_table.addDefinition(
            const_decl.name,
            const_decl.name_loc.line,
            const_decl.name_loc.column,
            const_decl.name.len,
        );
    }
};

test {
    _ = @import("declaration_pass_test.zig");
}
