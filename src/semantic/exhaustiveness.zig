const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");
const compilation_ctx = @import("../context.zig");

pub const ExhaustivenessChecker = struct {
    symbols: *symbol_table.SymbolTable,
    domains: *error_domains.ErrorDomainTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,

    // compilation context for arena-based memory management
    compilation_context: *compilation_ctx.CompilationContext,

    pub fn init(
        ctx: *compilation_ctx.CompilationContext,
        symbols: *symbol_table.SymbolTable,
        domains: *error_domains.ErrorDomainTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) ExhaustivenessChecker {
        return .{
            .symbols = symbols,
            .domains = domains,
            .diagnostics_list = diagnostics_list,
            .allocator = ctx.permanentAllocator(),
            .source_file = source_file,
            .compilation_context = ctx,
        };
    }

    pub fn checkModule(self: *ExhaustivenessChecker, module: ast.Module) !void {
        for (module.statements) |stmt| {
            try self.checkStmt(stmt);
        }
    }

    pub fn checkStmt(self: *ExhaustivenessChecker, stmt: ast.Stmt) !void {
        switch (stmt) {
            .match_stmt => |ms| try self.checkMatch(ms),
            .function_decl => |fd| {
                for (fd.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .if_stmt => |is| {
                for (is.then_block) |then_stmt| {
                    try self.checkStmt(then_stmt);
                }
                if (is.else_block) |else_block| {
                    for (else_block) |else_stmt| {
                        try self.checkStmt(else_stmt);
                    }
                }
            },
            .while_stmt => |ws| {
                for (ws.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .for_stmt => |fs| {
                for (fs.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .expr_stmt => |expr| try self.checkExpr(expr),
            else => {},
        }
    }

    fn checkExpr(self: *ExhaustivenessChecker, expr: *ast.Expr) !void {
        switch (expr.*) {
            .match_expr => |me| try self.checkMatchExpr(me),
            .call => |ce| {
                try self.checkExpr(ce.callee);
                for (ce.args) |arg| {
                    try self.checkExpr(arg);
                }
            },
            .binary => |be| {
                try self.checkExpr(be.left);
                try self.checkExpr(be.right);
            },
            .unary => |ue| {
                try self.checkExpr(ue.operand);
            },
            .field_access => |fa| {
                try self.checkExpr(fa.object);
            },
            .ok => |ok_expr| {
                try self.checkExpr(ok_expr);
            },
            .check => |ce| {
                try self.checkExpr(ce.expr);
            },
            .ensure => |ee| {
                try self.checkExpr(ee.condition);
            },
            else => {},
        }
    }

    pub fn checkMatch(self: *ExhaustivenessChecker, match_stmt: ast.MatchStmt) !void {
        try self.checkArmsExhaustiveness(match_stmt.arms, match_stmt.value, "match statement");
    }

    pub fn checkMatchExpr(self: *ExhaustivenessChecker, match_expr: ast.MatchExpr) !void {
        try self.checkArmsExhaustiveness(match_expr.arms, match_expr.value, "match expression");
    }

    /// checks if match arms are exhaustive for the given matched value
    fn checkArmsExhaustiveness(self: *ExhaustivenessChecker, arms: []ast.MatchArm, matched_value: *ast.Expr, match_context: []const u8) !void {
        var covered_variants = std.StringHashMap(void).init(self.allocator);
        defer covered_variants.deinit();

        var has_wildcard = false;
        var has_identifier_binding = false;

        // collect covered patterns
        for (arms) |arm| {
            switch (arm.pattern) {
                .wildcard => has_wildcard = true,
                .identifier => has_identifier_binding = true,
                .variant => |v| {
                    try covered_variants.put(v.name, {});
                },
                .ok_pattern => {
                    try covered_variants.put("ok", {});
                },
                .err_pattern => {
                    try covered_variants.put("err", {});
                },
                .some_pattern => {
                    try covered_variants.put("Some", {});
                },
                .none_pattern => {
                    try covered_variants.put("None", {});
                },
                .number, .string => {
                    // literal patterns don't provide exhaustiveness for union types
                },
            }
        }

        // wildcard or identifier binding covers all cases
        if (has_wildcard or has_identifier_binding) {
            return;
        }

        // try to determine the type being matched and check exhaustiveness
        const matched_type_opt = self.inferMatchedType(matched_value);
        if (matched_type_opt) |matched_type| {
            try self.checkTypeExhaustiveness(matched_type, covered_variants, match_context);
        } else {
            // type could not be determined, issue a general warning
            try self.diagnostics_list.addWarning(
                try std.fmt.allocPrint(
                    self.allocator,
                    "{s} may not be exhaustive",
                    .{match_context},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                try self.allocator.dupe(u8, "consider adding a wildcard pattern '_' to handle all cases"),
            );
        }
    }

    /// infers the type of the matched expression by looking up identifiers
    fn inferMatchedType(self: *ExhaustivenessChecker, expr: *ast.Expr) ?MatchedTypeInfo {
        switch (expr.*) {
            .identifier => |id| {
                // look up the identifier in the symbol table
                if (self.symbols.lookupGlobal(id.name)) |symbol| {
                    switch (symbol) {
                        .constant => |c| return self.extractTypeInfo(c.type_annotation),
                        .variable => |v| return self.extractTypeInfo(v.type_annotation),
                        .parameter => |p| return self.extractTypeInfo(p.type_annotation),
                        else => return null,
                    }
                }
                return null;
            },
            .call => |ce| {
                // for function calls, try to determine return type
                switch (ce.callee.*) {
                    .identifier => |callee_id| {
                        if (self.symbols.lookupGlobal(callee_id.name)) |symbol| {
                            if (symbol == .function) {
                                return self.extractTypeInfo(symbol.function.return_type);
                            }
                        }
                    },
                    else => {},
                }
                return null;
            },
            .field_access => |fa| {
                // could recursively resolve field access types
                _ = fa;
                return null;
            },
            else => return null,
        }
    }

    const MatchedTypeInfo = struct {
        kind: TypeKind,
        variants: ?[]const []const u8,

        const TypeKind = enum {
            union_type,
            result_type,
            nullable_type,
            other,
        };
    };

    /// extracts type information for exhaustiveness checking
    fn extractTypeInfo(self: *ExhaustivenessChecker, resolved_type: types.ResolvedType) ?MatchedTypeInfo {
        switch (resolved_type) {
            .union_type => |ut| {
                const variant_names = self.allocator.alloc([]const u8, ut.variants.len) catch return null;
                for (ut.variants, 0..) |variant, i| {
                    variant_names[i] = variant.name;
                }
                return MatchedTypeInfo{
                    .kind = .union_type,
                    .variants = variant_names,
                };
            },
            .named => |n| {
                // resolve named types to their underlying type
                return self.extractTypeInfo(n.underlying.*);
            },
            .result => {
                return MatchedTypeInfo{
                    .kind = .result_type,
                    .variants = &[_][]const u8{ "ok", "err" },
                };
            },
            .nullable => {
                return MatchedTypeInfo{
                    .kind = .nullable_type,
                    .variants = &[_][]const u8{ "Some", "None" },
                };
            },
            else => {
                return MatchedTypeInfo{
                    .kind = .other,
                    .variants = null,
                };
            },
        }
    }

    /// checks if all variants of a type are covered
    fn checkTypeExhaustiveness(self: *ExhaustivenessChecker, type_info: MatchedTypeInfo, covered: std.StringHashMap(void), match_context: []const u8) !void {
        if (type_info.variants == null) {
            // for non-variant types, just warn if no wildcard
            try self.diagnostics_list.addWarning(
                try std.fmt.allocPrint(
                    self.allocator,
                    "{s} may not be exhaustive",
                    .{match_context},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                try self.allocator.dupe(u8, "consider adding a wildcard pattern '_' to handle all cases"),
            );
            return;
        }

        const variants = type_info.variants.?;
        var missing_variants: std.ArrayList([]const u8) = .empty;
        defer missing_variants.deinit(self.allocator);

        for (variants) |variant_name| {
            if (!covered.contains(variant_name)) {
                try missing_variants.append(self.allocator, variant_name);
            }
        }

        if (missing_variants.items.len > 0) {
            var missing_str: std.ArrayList(u8) = .empty;
            defer missing_str.deinit(self.allocator);

            for (missing_variants.items, 0..) |name, i| {
                if (i > 0) {
                    try missing_str.appendSlice(self.allocator, ", ");
                }
                try missing_str.appendSlice(self.allocator, name);
            }

            const type_name = switch (type_info.kind) {
                .union_type => "union",
                .result_type => "Result",
                .nullable_type => "Maybe",
                .other => "type",
            };

            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "{s} is not exhaustive: missing {s} variant(s): {s}",
                    .{ match_context, type_name, missing_str.items },
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                try self.allocator.dupe(u8, "add cases for missing variants or use a wildcard '_' pattern"),
            );
        }
    }

    pub fn checkDomainExhaustiveness(
        self: *ExhaustivenessChecker,
        arms: []ast.MatchArm,
        domain_name: []const u8,
    ) !bool {
        if (self.domains.get(domain_name)) |domain| {
            var covered = std.StringHashMap(void).init(self.allocator);
            defer covered.deinit();

            var has_wildcard = false;

            for (arms) |arm| {
                switch (arm.pattern) {
                    .wildcard => has_wildcard = true,
                    .identifier => has_wildcard = true,
                    .variant => |v| {
                        try covered.put(v.name, {});
                    },
                    .err_pattern => |err| {
                        if (err.variant_name) |name| {
                            try covered.put(name, {});
                        }
                    },
                    else => {},
                }
            }

            if (has_wildcard) return true;

            var all_covered = true;
            for (domain.variants) |variant| {
                if (!covered.contains(variant.name)) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "match is not exhaustive: missing case for error variant '{s}' in domain '{s}'",
                            .{ variant.name, domain_name },
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        try self.allocator.dupe(u8, "add a case for this variant or use a wildcard '_' pattern"),
                    );
                    all_covered = false;
                }
            }

            return all_covered;
        }

        return false;
    }

    /// checks exhaustiveness for a union type given a type symbol name
    pub fn checkUnionExhaustiveness(
        self: *ExhaustivenessChecker,
        arms: []ast.MatchArm,
        type_name: []const u8,
    ) !bool {
        if (self.symbols.lookupGlobal(type_name)) |symbol| {
            if (symbol == .type_def) {
                const type_def = symbol.type_def;
                if (type_def.underlying == .union_type) {
                    var covered = std.StringHashMap(void).init(self.allocator);
                    defer covered.deinit();

                    var has_wildcard = false;

                    for (arms) |arm| {
                        switch (arm.pattern) {
                            .wildcard => has_wildcard = true,
                            .identifier => has_wildcard = true,
                            .variant => |v| {
                                try covered.put(v.name, {});
                            },
                            else => {},
                        }
                    }

                    if (has_wildcard) return true;

                    var all_covered = true;
                    for (type_def.underlying.union_type.variants) |variant| {
                        if (!covered.contains(variant.name)) {
                            try self.diagnostics_list.addError(
                                try std.fmt.allocPrint(
                                    self.allocator,
                                    "match is not exhaustive: missing case for variant '{s}' in union type '{s}'",
                                    .{ variant.name, type_name },
                                ),
                                .{
                                    .file = self.source_file,
                                    .line = 0,
                                    .column = 0,
                                    .length = 0,
                                },
                                try self.allocator.dupe(u8, "add a case for this variant or use a wildcard '_' pattern"),
                            );
                            all_covered = false;
                        }
                    }

                    return all_covered;
                }
            }
        }

        return false;
    }
};

test {}
