const std = @import("std");
const ast = @import("../ast.zig");
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
            .domain_decl => |dd| try self.collectDomain(dd),
            .role_decl => |rd| try self.collectRole(rd),
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

        const is_capability = try self.allocator.alloc(bool, func.params.len);
        errdefer self.allocator.free(is_capability);

        for (func.params, 0..) |param, i| {
            is_capability[i] = param.is_capability;
            params[i] = .unit_type;
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
                self.allocator.free(params);
                return;
            }
        }

        const symbol = symbol_table.Symbol{
            .function = .{
                .name = func.name,
                .params = params,
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

        const symbol = symbol_table.Symbol{
            .type_def = .{
                .name = type_decl.name,
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

        const variants = try self.allocator.alloc(error_domains.ErrorVariant, domain.variants.len);
        for (domain.variants, 0..) |variant, i| {
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

        try self.location_table.addDefinition(
            domain.name,
            domain.name_loc.line,
            domain.name_loc.column,
            domain.name.len,
        );
    }

    pub fn collectRole(self: *DeclarationCollector, role: ast.RoleDecl) !void {
        if (self.symbols.lookupGlobal(role.name)) |_| {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "duplicate declaration of role '{s}'",
                    .{role.name},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = role.name.len,
                },
                null,
            );
            return;
        }

        const symbol = symbol_table.Symbol{
            .role = .{
                .name = role.name,
            },
        };

        try self.symbols.insertGlobal(role.name, symbol);
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
