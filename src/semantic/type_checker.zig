const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");
const typed_ast = @import("../typed_ast.zig");
const type_resolver = @import("type_resolver.zig");
const hover_info = @import("../hover_info.zig");
const symbol_locations = @import("../symbol_locations.zig");
const context = @import("../context.zig");

pub const TypeChecker = struct {
    symbols: *symbol_table.SymbolTable,
    current_scope: *symbol_table.Scope,
    current_function: ?*symbol_table.FunctionSymbol,
    current_function_error_domain: ?[]const u8,
    domains: ?*error_domains.ErrorDomainTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    type_resolver: type_resolver.TypeResolver,
    hover_table: *hover_info.HoverInfoTable,
    location_table: *symbol_locations.SymbolLocationTable,

    // compilation context for arena-based memory management
    // types are interned for deduplication and simplified cleanup
    compilation_context: *context.CompilationContext,

    pub fn init(
        ctx: *context.CompilationContext,
        symbols: *symbol_table.SymbolTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
        hover_table: *hover_info.HoverInfoTable,
        location_table: *symbol_locations.SymbolLocationTable,
    ) TypeChecker {
        return .{
            .symbols = symbols,
            .current_scope = &symbols.global_scope,
            .current_function = null,
            .current_function_error_domain = null,
            .domains = null,
            .diagnostics_list = diagnostics_list,
            .allocator = ctx.permanentAllocator(),
            .source_file = source_file,
            .type_resolver = type_resolver.TypeResolver.init(ctx, symbols, diagnostics_list, source_file),
            .hover_table = hover_table,
            .location_table = location_table,
            .compilation_context = ctx,
        };
    }

    // interns a type in the context's arena
    fn internType(self: *TypeChecker, resolved_type: types.ResolvedType) !types.ResolvedType {
        const interned = try self.compilation_context.internType(resolved_type);
        return interned.*;
    }

    // creates a scope using the context
    fn createScope(self: *TypeChecker, parent: ?*symbol_table.Scope, scope_level: u32) symbol_table.Scope {
        return symbol_table.Scope.init(self.compilation_context, parent, scope_level);
    }

    pub fn setDomainTable(self: *TypeChecker, domains: *error_domains.ErrorDomainTable) void {
        self.domains = domains;
    }

    pub fn checkModule(self: *TypeChecker, module: ast.Module) std.mem.Allocator.Error!typed_ast.TypedModule {
        var typed_stmts = std.ArrayList(typed_ast.TypedStmt){};
        typed_stmts.clearRetainingCapacity();
        errdefer typed_stmts.deinit(self.allocator);

        for (module.statements) |stmt| {
            const typed_stmt = try self.checkStmt(stmt);
            try typed_stmts.append(self.allocator, typed_stmt);
        }

        return typed_ast.TypedModule{
            .statements = try typed_stmts.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    pub fn checkStmt(self: *TypeChecker, stmt: ast.Stmt) std.mem.Allocator.Error!typed_ast.TypedStmt {
        switch (stmt) {
            .function_decl => |fd| try self.checkFunctionDecl(fd),
            .const_decl => |cd| try self.checkConstDecl(cd),
            .var_decl => |vd| try self.checkVarDecl(vd),
            .return_stmt => |return_stmt| try self.checkReturnStmt(return_stmt),
            .expr_stmt => |expr| try self.checkExprStmt(expr),
            .assign_stmt => |as| try self.checkAssignStmt(as),
            .if_stmt => |is| try self.checkIfStmt(is),
            .while_stmt => |ws| try self.checkWhileStmt(ws),
            .for_stmt => |fs| try self.checkForStmt(fs),
            .match_stmt => |ms| try self.checkMatchStmt(ms),
            else => {},
        }

        return typed_ast.TypedStmt{
            .stmt = stmt,
            .type_info = null,
            .allocator = self.allocator,
        };
    }

    fn checkFunctionDecl(self: *TypeChecker, func: ast.FunctionDecl) !void {
        var new_scope = self.createScope(self.current_scope, self.current_scope.scope_level + 1);
        defer new_scope.deinit();

        const prev_scope = self.current_scope;
        defer self.current_scope = prev_scope;
        self.current_scope = &new_scope;

        // get the function symbol which already has resolved parameter types from Pass 2
        const func_symbol_opt = self.symbols.lookupGlobal(func.name);
        if (func_symbol_opt) |symbol| {
            if (symbol == .function) {
                var func_symbol = symbol.function;
                self.current_function = &func_symbol;
                self.current_function_error_domain = func_symbol.error_domain;

                // collect parameter names for hover
                var param_names = try self.allocator.alloc([]const u8, func.params.len);
                defer self.allocator.free(param_names);
                for (func.params, 0..) |param, i| {
                    param_names[i] = param.name;
                }

                // add function hover info
                try self.hover_table.addFunction(
                    func.name_loc.line,
                    func.name_loc.column,
                    func.name.len,
                    func.name,
                    func_symbol.params,
                    param_names,
                    func_symbol.return_type,
                    func_symbol.effects,
                    func_symbol.error_domain,
                );

                // use already-resolved parameter types from Pass 2
                for (func.params, func_symbol.params) |param, param_type| {
                    // use cloneOrIntern to handle ownership correctly
                    // when context is available, type is interned and shared
                    // otherwise, clone so the local scope owns its own copy
                    const local_type = try self.internType(param_type);
                    const param_symbol = symbol_table.Symbol{
                        .parameter = .{
                            .name = param.name,
                            .type_annotation = local_type,
                            .is_inout = param.is_inout,
                            .is_capability = param.is_capability,
                        },
                    };
                    try self.current_scope.insert(param.name, param_symbol);

                    // add parameter hover info
                    try self.hover_table.add(
                        param.name_loc.line,
                        param.name_loc.column,
                        param.name.len,
                        param.name,
                        .parameter,
                        param_type,
                    );
                }
            }
        }

        for (func.body) |body_stmt| {
            _ = try self.checkStmt(body_stmt);
        }

        self.current_function = null;
        self.current_function_error_domain = null;
    }

    fn checkConstDecl(self: *TypeChecker, const_decl: ast.ConstDecl) !void {
        const value_typed = try self.checkExpr(const_decl.value);
        defer self.allocator.free(value_typed.effects);

        // types are interned via context and don't need manual cleanup

        // require explicit type annotation for numeric literals
        if (const_decl.type_annotation == null and self.isNumericLiteral(const_decl.value)) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "numeric literal requires explicit type annotation: const {s}: <type> = ...",
                    .{const_decl.name},
                ),
                .{
                    .file = self.source_file,
                    .line = const_decl.name_loc.line,
                    .column = const_decl.name_loc.column,
                    .length = const_decl.name.len,
                },
                try self.allocator.dupe(u8, "specify the type explicitly to avoid ambiguity (e.g., u32, i32, f64)"),
            );
        }

        var final_type = value_typed.resolved_type;

        if (const_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            final_type = declared_type;

            // allow numeric literals to unify with the declared type
            if (!declared_type.eql(&value_typed.resolved_type)) {
                if (!self.canUnifyNumericLiteral(const_decl.value, &value_typed.resolved_type, &declared_type)) {
                    const expected_str = try declared_type.toStr(self.allocator);
                    defer self.allocator.free(expected_str);
                    const got_str = try value_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(got_str);
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in constant declaration: expected {s}, got {s}",
                            .{ expected_str, got_str },
                        ),
                        .{
                            .file = self.source_file,
                            .line = const_decl.name_loc.line,
                            .column = const_decl.name_loc.column,
                            .length = const_decl.name.len,
                        },
                        null,
                    );
                }
            }
        }

        const const_symbol = symbol_table.Symbol{
            .constant = .{
                .name = const_decl.name,
                .type_annotation = final_type,
                .scope_level = self.current_scope.scope_level,
            },
        };

        try self.current_scope.insert(const_decl.name, const_symbol);

        try self.hover_table.add(
            const_decl.name_loc.line,
            const_decl.name_loc.column,
            const_decl.name.len,
            const_decl.name,
            .constant,
            final_type,
        );
    }

    pub fn checkVarDecl(self: *TypeChecker, var_decl: ast.VarDecl) !void {
        const value_typed = try self.checkExpr(var_decl.value);
        defer self.allocator.free(value_typed.effects);

        // types are interned via context and don't need manual cleanup

        // require explicit type annotation for numeric literals
        if (var_decl.type_annotation == null and self.isNumericLiteral(var_decl.value)) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "numeric literal requires explicit type annotation: var {s}: <type> = ...",
                    .{var_decl.name},
                ),
                .{
                    .file = self.source_file,
                    .line = var_decl.name_loc.line,
                    .column = var_decl.name_loc.column,
                    .length = var_decl.name.len,
                },
                try self.allocator.dupe(u8, "specify the type explicitly to avoid ambiguity (e.g., u32, i32, f64)"),
            );
        }

        var final_type = value_typed.resolved_type;

        if (var_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            final_type = declared_type;

            // allow numeric literals to unify with the declared type
            if (!declared_type.eql(&value_typed.resolved_type)) {
                if (!self.canUnifyNumericLiteral(var_decl.value, &value_typed.resolved_type, &declared_type)) {
                    const expected_str = try declared_type.toStr(self.allocator);
                    defer self.allocator.free(expected_str);
                    const got_str = try value_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(got_str);
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in variable declaration: expected {s}, got {s}",
                            .{ expected_str, got_str },
                        ),
                        .{
                            .file = self.source_file,
                            .line = var_decl.name_loc.line,
                            .column = var_decl.name_loc.column,
                            .length = var_decl.name.len,
                        },
                        null,
                    );
                }
            }
        }

        const var_symbol = symbol_table.Symbol{
            .variable = .{
                .name = var_decl.name,
                .type_annotation = final_type,
                .is_mutable = true,
                .scope_level = self.current_scope.scope_level,
            },
        };

        try self.current_scope.insert(var_decl.name, var_symbol);

        try self.hover_table.add(
            var_decl.name_loc.line,
            var_decl.name_loc.column,
            var_decl.name.len,
            var_decl.name,
            .variable,
            final_type,
        );
    }

    pub fn checkReturnStmt(self: *TypeChecker, return_stmt: ast.ReturnStmt) !void {
        if (self.current_function) |func| {
            if (return_stmt.value) |expr| {
                var expr_typed = try self.checkExpr(expr);
                defer expr_typed.deinit();

                // for functions with error domains, validate the Result's ok_type matches the declared return type
                if (self.current_function_error_domain != null) {
                    if (expr_typed.resolved_type == .result) {
                        const result_ok_type = expr_typed.resolved_type.result.ok_type;

                        // err expressions return Result<Unit, E> which is valid for any return type
                        // since the error path never produces a value
                        const is_error_return = result_ok_type.* == .unit_type and expr.* == .err;

                        const types_match = is_error_return or
                            func.return_type.eql(result_ok_type) or
                            self.canUnifyNumericLiteral(expr, result_ok_type, &func.return_type);

                        if (!types_match) {
                            var expected_buf = std.ArrayList(u8){};
                            defer expected_buf.deinit(self.allocator);
                            try func.return_type.format("", .{}, expected_buf.writer(self.allocator));

                            var got_buf = std.ArrayList(u8){};
                            defer got_buf.deinit(self.allocator);
                            try result_ok_type.format("", .{}, got_buf.writer(self.allocator));

                            try self.diagnostics_list.addError(
                                try std.fmt.allocPrint(
                                    self.allocator,
                                    "return type mismatch: expected ok type {s}, got {s}",
                                    .{ expected_buf.items, got_buf.items },
                                ),
                                .{
                                    .file = self.source_file,
                                    .line = return_stmt.loc.line,
                                    .column = return_stmt.loc.column,
                                    .length = 6,
                                },
                                null,
                            );
                        }
                    } else {
                        // in a function with error domain, must return via ok/err
                        try self.diagnostics_list.addError(
                            try self.allocator.dupe(u8, "functions with error clause must return via 'ok' or 'err'"),
                            .{
                                .file = self.source_file,
                                .line = return_stmt.loc.line,
                                .column = return_stmt.loc.column,
                                .length = 6,
                            },
                            null,
                        );
                    }
                } else {
                    // no error domain - standard return type checking
                    const types_match = func.return_type.eql(&expr_typed.resolved_type) or
                        self.canUnifyNumericLiteral(expr, &expr_typed.resolved_type, &func.return_type);

                    if (!types_match) {
                        var expected_buf = std.ArrayList(u8){};
                        defer expected_buf.deinit(self.allocator);
                        try func.return_type.format("", .{}, expected_buf.writer(self.allocator));

                        var got_buf = std.ArrayList(u8){};
                        defer got_buf.deinit(self.allocator);
                        try expr_typed.resolved_type.format("", .{}, got_buf.writer(self.allocator));

                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "return type mismatch: expected {s}, got {s}",
                                .{ expected_buf.items, got_buf.items },
                            ),
                            .{
                                .file = self.source_file,
                                .line = return_stmt.loc.line,
                                .column = return_stmt.loc.column,
                                .length = 6,
                            },
                            null,
                        );
                    }
                }
            } else {
                if (func.return_type != .unit_type) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "return statement must have a value"),
                        .{
                            .file = self.source_file,
                            .line = return_stmt.loc.line,
                            .column = return_stmt.loc.column,
                            .length = 6,
                        },
                        null,
                    );
                }
            }
        }
    }

    fn checkExprStmt(self: *TypeChecker, expr: *ast.Expr) !void {
        var typed_expr = try self.checkExpr(expr);
        typed_expr.deinit();
    }

    pub fn checkAssignStmt(self: *TypeChecker, assign: ast.AssignStmt) !void {
        var value_typed = try self.checkExpr(assign.value);
        defer value_typed.deinit();

        // track reference to the assignment target
        try self.location_table.addReference(
            assign.target.name,
            assign.target.loc.line,
            assign.target.loc.column,
            assign.target.name.len,
        );

        if (self.current_scope.lookup(assign.target.name)) |symbol| {
            switch (symbol) {
                .variable => |v| {
                    try self.hover_table.add(
                        assign.target.loc.line,
                        assign.target.loc.column,
                        assign.target.name.len,
                        assign.target.name,
                        .variable,
                        v.type_annotation,
                    );

                    if (!v.is_mutable) {
                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "cannot assign to immutable variable '{s}'",
                                .{assign.target.name},
                            ),
                            .{
                                .file = self.source_file,
                                .line = assign.target.loc.line,
                                .column = assign.target.loc.column,
                                .length = assign.target.name.len,
                            },
                            null,
                        );
                    }
                    if (!v.type_annotation.eql(&value_typed.resolved_type)) {
                        const expected_str = try v.type_annotation.toStr(self.allocator);
                        defer self.allocator.free(expected_str);
                        const got_str = try value_typed.resolved_type.toStr(self.allocator);
                        defer self.allocator.free(got_str);
                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "type mismatch in assignment: expected {s}, got {s}",
                                .{ expected_str, got_str },
                            ),
                            .{
                                .file = self.source_file,
                                .line = assign.target.loc.line,
                                .column = assign.target.loc.column,
                                .length = assign.target.name.len,
                            },
                            null,
                        );
                    }
                },
                else => {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "cannot assign to '{s}': not a variable",
                            .{assign.target.name},
                        ),
                        .{
                            .file = self.source_file,
                            .line = assign.target.loc.line,
                            .column = assign.target.loc.column,
                            .length = assign.target.name.len,
                        },
                        null,
                    );
                },
            }
        } else {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "undefined variable '{s}'",
                    .{assign.target.name},
                ),
                .{
                    .file = self.source_file,
                    .line = assign.target.loc.line,
                    .column = assign.target.loc.column,
                    .length = assign.target.name.len,
                },
                null,
            );
        }
    }

    pub fn checkIfStmt(self: *TypeChecker, if_stmt: ast.IfStmt) !void {
        var condition_typed = try self.checkExpr(if_stmt.condition);
        defer condition_typed.deinit();
        const cond_loc = if_stmt.condition.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 0 };
        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "if condition must be Bool, got {any}",
                    .{condition_typed.resolved_type},
                ),
                .{
                    .file = self.source_file,
                    .line = cond_loc.line,
                    .column = cond_loc.column,
                    .length = cond_loc.length,
                },
                null,
            );
        }

        for (if_stmt.then_block) |stmt| {
            _ = try self.checkStmt(stmt);
        }

        if (if_stmt.else_block) |else_block| {
            for (else_block) |stmt| {
                _ = try self.checkStmt(stmt);
            }
        }
    }

    pub fn checkWhileStmt(self: *TypeChecker, while_stmt: ast.WhileStmt) !void {
        var condition_typed = try self.checkExpr(while_stmt.condition);
        defer condition_typed.deinit();
        const cond_loc = while_stmt.condition.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 0 };
        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "while condition must be Bool, got {any}",
                    .{condition_typed.resolved_type},
                ),
                .{
                    .file = self.source_file,
                    .line = cond_loc.line,
                    .column = cond_loc.column,
                    .length = cond_loc.length,
                },
                null,
            );
        }

        for (while_stmt.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
    }

    fn checkForStmt(self: *TypeChecker, for_stmt: ast.ForStmt) !void {
        var iterable_typed = try self.checkExpr(for_stmt.iterable);

        var new_scope = self.createScope(self.current_scope, self.current_scope.scope_level + 1);
        defer new_scope.deinit();

        const prev_scope = self.current_scope;
        defer self.current_scope = prev_scope;
        self.current_scope = &new_scope;

        // types are arena-managed via compilation context, no clone needed
        const element_type = switch (iterable_typed.resolved_type) {
            .array => |arr| arr.element_type.*,
            .view => |view| view.element_type.*,
            .range => |r| r.element_type.*,
            else => types.ResolvedType.unit_type,
        };
        defer iterable_typed.deinit();

        // add iterator variable to scope
        const iterator_symbol = symbol_table.Symbol{
            .constant = .{
                .name = for_stmt.iterator,
                .type_annotation = element_type,
                .scope_level = self.current_scope.scope_level,
            },
        };
        try self.current_scope.insert(for_stmt.iterator, iterator_symbol);

        // add hover info for iterator variable
        try self.hover_table.add(
            for_stmt.iterator_loc.line,
            for_stmt.iterator_loc.column,
            for_stmt.iterator.len,
            for_stmt.iterator,
            .constant,
            element_type,
        );

        for (for_stmt.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
    }

    fn checkMatchStmt(self: *TypeChecker, match_stmt: ast.MatchStmt) !void {
        var value_typed = try self.checkExpr(match_stmt.value);
        defer value_typed.deinit();

        // types are arena-managed, no clone needed
        const match_type = value_typed.resolved_type;

        for (match_stmt.arms) |arm| {
            // validate pattern against the matched value type
            try self.checkPattern(arm.pattern, match_type);

            // create a new scope for each arm to bind pattern variables
            var arm_scope = self.createScope(self.current_scope, self.current_scope.scope_level + 1);
            defer arm_scope.deinit();

            const prev_scope = self.current_scope;
            defer self.current_scope = prev_scope;
            self.current_scope = &arm_scope;

            // bind pattern variables to the arm scope
            try self.bindPatternVariables(arm.pattern, match_type);

            var arm_typed = try self.checkExpr(arm.body);
            defer arm_typed.deinit();
        }
    }

    /// validates that a pattern is compatible with the matched type
    fn checkPattern(self: *TypeChecker, pattern: ast.Pattern, match_type: types.ResolvedType) !void {
        switch (pattern) {
            .wildcard, .identifier => {
                // wildcard and identifier patterns match any type
            },
            .number => {
                // number patterns should match integer or float types
                const is_numeric = switch (match_type) {
                    .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64 => true,
                    else => false,
                };
                if (!is_numeric) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "number pattern cannot match non-numeric type"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            },
            .string => {
                // string patterns should match string type
                if (match_type != .string_type) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "string pattern cannot match non-string type"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            },
            .variant => |v| {
                // variant patterns should match union types
                try self.checkVariantPattern(v.name, v.fields, match_type);
            },
            .ok_pattern, .err_pattern => {
                // result patterns should match result types
                if (match_type != .result) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "ok/err pattern can only match Result types"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            },
            .some_pattern, .none_pattern => {
                // maybe patterns should match nullable types
                if (match_type != .nullable) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "Some/None pattern can only match Maybe (nullable) types"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            },
        }
    }

    /// checks that a variant pattern matches a valid variant in the union type
    fn checkVariantPattern(self: *TypeChecker, variant_name: []const u8, pattern_fields: ?[]ast.PatternField, match_type: types.ResolvedType) !void {
        // resolve named types to their underlying union type
        const union_type = switch (match_type) {
            .union_type => match_type,
            .named => |n| if (n.underlying.* == .union_type) n.underlying.* else {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "variant pattern '{s}' cannot match non-union type",
                        .{variant_name},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
                return;
            },
            else => {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "variant pattern '{s}' cannot match non-union type",
                        .{variant_name},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
                return;
            },
        };

        // find the variant in the union type
        var found_variant: ?types.UnionVariantInfo = null;
        for (union_type.union_type.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                found_variant = variant;
                break;
            }
        }

        if (found_variant == null) {
            var variant_names: std.ArrayList(u8) = .empty;
            defer variant_names.deinit(self.allocator);
            for (union_type.union_type.variants, 0..) |variant, i| {
                if (i > 0) {
                    try variant_names.appendSlice(self.allocator, ", ");
                }
                try variant_names.appendSlice(self.allocator, variant.name);
            }
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "unknown variant '{s}' in pattern. available variants: {s}",
                    .{ variant_name, variant_names.items },
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                null,
            );
            return;
        }

        const variant = found_variant.?;

        // check pattern fields match variant fields
        if (pattern_fields) |fields| {
            for (fields) |pattern_field| {
                var field_found = false;
                for (variant.field_names) |field_name| {
                    if (std.mem.eql(u8, field_name, pattern_field.name)) {
                        field_found = true;
                        break;
                    }
                }
                if (!field_found) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "variant '{s}' has no field named '{s}'",
                            .{ variant_name, pattern_field.name },
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            }
        }
    }

    /// binds variables from a pattern to the current scope
    fn bindPatternVariables(self: *TypeChecker, pattern: ast.Pattern, match_type: types.ResolvedType) !void {
        switch (pattern) {
            .identifier => |name| {
                // bind the matched value to this name
                // types are arena-managed, no clone needed
                const var_symbol = symbol_table.Symbol{
                    .constant = .{
                        .name = name,
                        .type_annotation = match_type,
                        .scope_level = self.current_scope.scope_level,
                    },
                };
                try self.current_scope.insert(name, var_symbol);
            },
            .variant => |v| {
                // bind variant fields to local variables
                try self.bindVariantFields(v.name, v.fields, match_type);
            },
            .ok_pattern => |ok| {
                if (ok.binding) |binding_name| {
                    if (match_type == .result) {
                        // types are arena-managed, no clone needed
                        const var_symbol = symbol_table.Symbol{
                            .constant = .{
                                .name = binding_name,
                                .type_annotation = match_type.result.ok_type.*,
                                .scope_level = self.current_scope.scope_level,
                            },
                        };
                        try self.current_scope.insert(binding_name, var_symbol);
                    }
                }
            },
            .err_pattern => |err| {
                if (err.fields) |fields| {
                    for (fields) |field| {
                        // bind error fields - for now just bind as unit type
                        // proper error domain field resolution would require more context
                        const var_symbol = symbol_table.Symbol{
                            .constant = .{
                                .name = field.name,
                                .type_annotation = types.ResolvedType.unit_type,
                                .scope_level = self.current_scope.scope_level,
                            },
                        };
                        try self.current_scope.insert(field.name, var_symbol);
                    }
                }
            },
            .some_pattern => |some| {
                if (some.binding) |binding_name| {
                    if (match_type == .nullable) {
                        // types are arena-managed, no clone needed
                        const var_symbol = symbol_table.Symbol{
                            .constant = .{
                                .name = binding_name,
                                .type_annotation = match_type.nullable.*,
                                .scope_level = self.current_scope.scope_level,
                            },
                        };
                        try self.current_scope.insert(binding_name, var_symbol);
                    }
                }
            },
            .wildcard, .number, .string, .none_pattern => {
                // these patterns don't bind any variables
            },
        }
    }

    /// binds variant fields to local scope variables
    fn bindVariantFields(self: *TypeChecker, variant_name: []const u8, pattern_fields: ?[]ast.PatternField, match_type: types.ResolvedType) !void {
        // resolve to union type
        const union_type = switch (match_type) {
            .union_type => match_type,
            .named => |n| if (n.underlying.* == .union_type) n.underlying.* else return,
            else => return,
        };

        // find the variant
        var found_variant: ?types.UnionVariantInfo = null;
        for (union_type.union_type.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                found_variant = variant;
                break;
            }
        }

        if (found_variant == null) return;
        const variant = found_variant.?;

        if (pattern_fields) |fields| {
            for (fields) |pattern_field| {
                // find the field type in the variant
                for (variant.field_names, 0..) |field_name, i| {
                    if (std.mem.eql(u8, field_name, pattern_field.name)) {
                        // types are arena-managed, no clone needed
                        const var_symbol = symbol_table.Symbol{
                            .constant = .{
                                .name = pattern_field.name,
                                .type_annotation = variant.field_types[i],
                                .scope_level = self.current_scope.scope_level,
                            },
                        };
                        try self.current_scope.insert(pattern_field.name, var_symbol);
                        break;
                    }
                }
            }
        }
    }

    pub fn checkExpr(self: *TypeChecker, expr: *ast.Expr) std.mem.Allocator.Error!typed_ast.TypedExpr {
        const resolved_type = switch (expr.*) {
            .number => try self.inferNumberType(expr.number),
            .string => types.ResolvedType.string_type,
            .bytes => types.ResolvedType.bytes_type,
            .char => types.ResolvedType.char_type,
            .bool_literal => types.ResolvedType.bool_type,
            .null_literal => types.ResolvedType.unit_type,
            .unit_literal => types.ResolvedType.unit_type,
            .identifier => |id| try self.checkIdentifier(id),
            .binary => |be| try self.checkBinary(be),
            .unary => |ue| try self.checkUnary(ue),
            .call => |ce| try self.checkCall(ce),
            .field_access => |fa| try self.checkFieldAccess(fa),
            .index_access => |ia| try self.checkIndexAccess(ia),
            .array_literal => |al| try self.checkArrayLiteral(al),
            .record_literal => |rl| try self.checkRecordLiteral(rl),
            .variant_constructor => |vc| try self.checkVariantConstructor(vc),
            .range => |r| try self.checkRange(r),
            .ok => |ok_expr| try self.checkOk(ok_expr),
            .err => |ee| try self.checkErr(ee),
            .check => |ce| try self.checkCheck(ce),
            .ensure => |ee| try self.checkEnsure(ee),
            .map_error => |me| try self.checkMapError(me),
            .match_expr => |me| try self.checkMatchExpr(me),
            .anonymous_function => |af| try self.checkAnonymousFunction(af),
            .unsafe_cast => |uc| try self.checkUnsafeCast(uc),
            .comptime_expr => |ce| try self.checkComptimeExpr(ce),
            .context_block => |cb| try self.checkContextBlock(cb),
            .block_expr => |be| try self.checkBlockExpr(be),
        };

        // types are always interned via context, TypedExpr doesn't own them

        return typed_ast.TypedExpr{
            .expr = expr,
            .resolved_type = resolved_type,
            .effects = &[_]types.Effect{},
            .allocator = self.allocator,
        };
    }

    fn inferNumberType(self: *TypeChecker, num_str: []const u8) !types.ResolvedType {
        _ = self;
        if (std.mem.indexOfScalar(u8, num_str, '.') != null) {
            return types.ResolvedType.f64;
        }
        return types.ResolvedType.i32;
    }

    fn checkIdentifier(self: *TypeChecker, id_expr: ast.IdentifierExpr) !types.ResolvedType {
        const id = id_expr.name;
        if (self.current_scope.lookup(id)) |symbol| {
            const resolved_type = switch (symbol) {
                .variable => |v| v.type_annotation,
                .constant => |c| c.type_annotation,
                .parameter => |p| p.type_annotation,
                .function => |f| f.return_type,
                else => {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "'{s}' is not a value",
                            .{id},
                        ),
                        .{
                            .file = self.source_file,
                            .line = id_expr.loc.line,
                            .column = id_expr.loc.column,
                            .length = id.len,
                        },
                        null,
                    );
                    return types.ResolvedType.unit_type;
                },
            };

            // add hover info and track reference
            const kind: hover_info.HoverKind = switch (symbol) {
                .variable => .variable,
                .constant => .constant,
                .parameter => .parameter,
                .function => .function,
                else => .variable,
            };

            try self.hover_table.add(
                id_expr.loc.line,
                id_expr.loc.column,
                id.len,
                id,
                kind,
                resolved_type,
            );

            try self.location_table.addReference(
                id,
                id_expr.loc.line,
                id_expr.loc.column,
                id.len,
            );

            // types are arena-managed, return directly without cloning
            return resolved_type;
        }

        try self.diagnostics_list.addError(
            try std.fmt.allocPrint(
                self.allocator,
                "undefined identifier '{s}'",
                .{id},
            ),
            .{
                .file = self.source_file,
                .line = id_expr.loc.line,
                .column = id_expr.loc.column,
                .length = id.len,
            },
            null,
        );
        return types.ResolvedType.unit_type;
    }

    fn checkBinary(self: *TypeChecker, binary: ast.BinaryExpr) !types.ResolvedType {
        var left_typed = try self.checkExpr(binary.left);
        defer self.allocator.free(left_typed.effects);
        var right_typed = try self.checkExpr(binary.right);
        defer self.allocator.free(right_typed.effects);

        // compute span covering the entire binary expression
        const left_loc = binary.left.getLocation();
        const right_loc = binary.right.getLocation();
        const loc = blk: {
            if (left_loc) |ll| {
                if (right_loc) |rl| {
                    // if on same line, compute full span
                    if (ll.line == rl.line) {
                        const end_col = rl.column + rl.length;
                        break :blk ast.Location{
                            .line = ll.line,
                            .column = ll.column,
                            .length = if (end_col > ll.column) end_col - ll.column else ll.length,
                        };
                    }
                }
                break :blk ll;
            }
            break :blk ast.Location{ .line = 0, .column = 0, .length = 0 };
        };

        switch (binary.op) {
            .add, .subtract, .multiply, .divide, .modulo, .concat => {
                // unify numeric literals
                if (self.isNumericLiteral(binary.left) and self.isNumericType(&right_typed.resolved_type)) {
                    // type is arena-managed, no cleanup needed;
                    return right_typed.resolved_type;
                }
                if (self.isNumericLiteral(binary.right) and self.isNumericType(&left_typed.resolved_type)) {
                    // type is arena-managed, no cleanup needed;
                    return left_typed.resolved_type;
                }

                // string concatenation
                if (binary.op == .concat) {
                    if (left_typed.resolved_type != .string_type or right_typed.resolved_type != .string_type) {
                        try self.diagnostics_list.addError(
                            try self.allocator.dupe(u8, "++ operator requires String operands"),
                            .{
                                .file = self.source_file,
                                .line = loc.line,
                                .column = loc.column,
                                .length = 2,
                            },
                            null,
                        );
                    }
                    // type is arena-managed, no cleanup needed;
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.string_type;
                }

                if (!left_typed.resolved_type.eql(&right_typed.resolved_type)) {
                    const left_str = try left_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(left_str);
                    const right_str = try right_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(right_str);
                    const hint = try std.fmt.allocPrint(
                        self.allocator,
                        "consider casting one operand to match the other type",
                        .{},
                    );
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in binary operation: {s} and {s}",
                            .{ left_str, right_str },
                        ),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = loc.length,
                        },
                        hint,
                    );
                }
                // type is arena-managed, no cleanup needed;
                return left_typed.resolved_type;
            },
            .eq, .ne, .lt, .gt, .le, .ge => {
                // unify numeric literals in comparisons
                const types_match = left_typed.resolved_type.eql(&right_typed.resolved_type) or
                    (self.isNumericLiteral(binary.left) and self.isNumericType(&right_typed.resolved_type)) or
                    (self.isNumericLiteral(binary.right) and self.isNumericType(&left_typed.resolved_type));

                if (!types_match) {
                    const left_str = try left_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(left_str);
                    const right_str = try right_typed.resolved_type.toStr(self.allocator);
                    defer self.allocator.free(right_str);
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in comparison: {s} and {s}",
                            .{ left_str, right_str },
                        ),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = loc.length,
                        },
                        null,
                    );
                }
                // type is arena-managed, no cleanup needed;
                // type is arena-managed, no cleanup needed;
                return types.ResolvedType.bool_type;
            },
            .logical_and, .logical_or => {
                if (left_typed.resolved_type != .bool_type or right_typed.resolved_type != .bool_type) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "logical operators require Bool operands"),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = loc.length,
                        },
                        null,
                    );
                }
                // type is arena-managed, no cleanup needed;
                // type is arena-managed, no cleanup needed;
                return types.ResolvedType.bool_type;
            },
            else => {
                // type is arena-managed, no cleanup needed;
                return left_typed.resolved_type;
            },
        }
    }

    fn checkUnary(self: *TypeChecker, unary: ast.UnaryExpr) !types.ResolvedType {
        const operand_typed = try self.checkExpr(unary.operand);
        defer self.allocator.free(operand_typed.effects);
        return operand_typed.resolved_type;
    }

    fn checkCall(self: *TypeChecker, call: ast.CallExpr) !types.ResolvedType {
        if (call.callee.* == .identifier) {
            const func_name = call.callee.identifier.name;
            const callee_loc = call.callee.identifier.loc;
            if (self.symbols.lookupGlobal(func_name)) |symbol| {
                if (symbol == .function) {
                    const func = symbol.function;

                    // add hover info for function call site
                    try self.hover_table.addFunction(
                        callee_loc.line,
                        callee_loc.column,
                        func_name.len,
                        func_name,
                        func.params,
                        func.param_names,
                        func.return_type,
                        func.effects,
                        func.error_domain,
                    );

                    // track reference for go-to-definition
                    try self.location_table.addReference(
                        func_name,
                        callee_loc.line,
                        callee_loc.column,
                        func_name.len,
                    );

                    if (call.args.len != func.params.len) {
                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "wrong number of arguments: expected {d}, got {d}",
                                .{ func.params.len, call.args.len },
                            ),
                            .{
                                .file = self.source_file,
                                .line = callee_loc.line,
                                .column = callee_loc.column,
                                .length = func_name.len,
                            },
                            null,
                        );
                        return types.ResolvedType.unit_type;
                    }

                    // check if this is a generic function
                    if (func.type_params) |type_params| {
                        // collect argument types for inference
                        // types are arena-managed, only free the array
                        var arg_types = try self.allocator.alloc(types.ResolvedType, call.args.len);
                        defer self.allocator.free(arg_types);

                        for (call.args, 0..) |arg, i| {
                            const arg_typed = try self.checkExpr(arg);
                            defer self.allocator.free(arg_typed.effects);
                            arg_types[i] = arg_typed.resolved_type;
                        }

                        // infer type arguments from argument types
                        const inferred = try self.inferTypeArgs(type_params, func.params, arg_types);
                        if (inferred) |inferred_args| {
                            // types are arena-managed, only free the array
                            defer self.allocator.free(inferred_args);

                            // substitute type params in return type
                            const param_names = try self.allocator.alloc([]const u8, type_params.len);
                            defer self.allocator.free(param_names);
                            for (type_params, 0..) |tp, i| {
                                param_names[i] = tp.name;
                            }

                            return try func.return_type.substitute(param_names, inferred_args, self.allocator);
                        }

                        return types.ResolvedType.unit_type;
                    }

                    // non-generic function - regular type checking
                    for (call.args, func.params, 0..) |arg, param_type, i| {
                        var arg_typed = try self.checkExpr(arg);
                        defer arg_typed.deinit();

                        // allow numeric literals to unify with parameter types
                        const types_match = arg_typed.resolved_type.eql(&param_type) or
                            self.canUnifyNumericLiteral(arg, &arg_typed.resolved_type, &param_type);

                        if (!types_match) {
                            const arg_loc = arg.getLocation();
                            const expected_str = try param_type.toStr(self.allocator);
                            defer self.allocator.free(expected_str);
                            const got_str = try arg_typed.resolved_type.toStr(self.allocator);
                            defer self.allocator.free(got_str);
                            const hint = try std.fmt.allocPrint(
                                self.allocator,
                                "expected {s} but found {s}",
                                .{ expected_str, got_str },
                            );
                            try self.diagnostics_list.addError(
                                try std.fmt.allocPrint(
                                    self.allocator,
                                    "argument {d} type mismatch: expected {s}, got {s}",
                                    .{ i, expected_str, got_str },
                                ),
                                .{
                                    .file = self.source_file,
                                    .line = if (arg_loc) |loc| loc.line else 0,
                                    .column = if (arg_loc) |loc| loc.column else 0,
                                    .length = if (arg_loc) |loc| loc.length else 0,
                                },
                                hint,
                            );
                        }
                    }

                    // if function has error domain, return Result<T, E>
                    if (func.error_domain) |domain| {
                        const ok_type_ptr = try self.allocator.create(types.ResolvedType);
                        ok_type_ptr.* = func.return_type;
                        return try self.internType(types.ResolvedType{
                            .result = .{
                                .ok_type = ok_type_ptr,
                                .error_domain = domain,
                            },
                        });
                    }

                    // types are arena-managed, return directly without cloning
                    return func.return_type;
                }
            }
        }

        return types.ResolvedType.unit_type;
    }

    /// infer type arguments for a generic function call
    fn inferTypeArgs(
        self: *TypeChecker,
        type_params: []const types.TypeParamInfo,
        param_types: []const types.ResolvedType,
        arg_types: []const types.ResolvedType,
    ) !?[]types.ResolvedType {
        if (type_params.len == 0) return null;
        if (param_types.len != arg_types.len) return null;

        const inferred = try self.allocator.alloc(types.ResolvedType, type_params.len);
        const inferred_flags = try self.allocator.alloc(bool, type_params.len);
        defer self.allocator.free(inferred_flags);

        for (inferred_flags) |*flag| {
            flag.* = false;
        }

        // try to infer each type parameter from arguments
        for (param_types, arg_types) |param, arg| {
            try self.inferFromPair(param, arg, type_params, inferred, inferred_flags);
        }

        // check all type params were inferred
        for (inferred_flags) |flag| {
            if (!flag) {
                // types are arena-managed, only free the array
                self.allocator.free(inferred);
                return null;
            }
        }

        return inferred;
    }

    fn inferFromPair(
        self: *TypeChecker,
        param_type: types.ResolvedType,
        arg_type: types.ResolvedType,
        type_params: []const types.TypeParamInfo,
        inferred: []types.ResolvedType,
        inferred_flags: []bool,
    ) !void {
        switch (param_type) {
            .type_param => |tp| {
                // found a type parameter - try to bind it
                for (type_params, 0..) |type_param, i| {
                    if (std.mem.eql(u8, tp.name, type_param.name)) {
                        if (!inferred_flags[i]) {
                            // types are arena-managed, no clone needed
                            inferred[i] = arg_type;
                            inferred_flags[i] = true;
                        }
                        break;
                    }
                }
            },
            .array => |a| {
                if (arg_type == .array) {
                    try self.inferFromPair(a.element_type.*, arg_type.array.element_type.*, type_params, inferred, inferred_flags);
                }
            },
            .view => |v| {
                if (arg_type == .view) {
                    try self.inferFromPair(v.element_type.*, arg_type.view.element_type.*, type_params, inferred, inferred_flags);
                }
            },
            .nullable => |n| {
                if (arg_type == .nullable) {
                    try self.inferFromPair(n.*, arg_type.nullable.*, type_params, inferred, inferred_flags);
                }
            },
            else => {},
        }
    }

    fn checkIndexAccess(self: *TypeChecker, index_access: ast.IndexAccessExpr) !types.ResolvedType {
        var object_typed = try self.checkExpr(index_access.object);
        defer self.allocator.free(object_typed.effects);
        var index_typed = try self.checkExpr(index_access.index);
        defer index_typed.deinit();

        const index_loc = index_access.index.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 0 };
        const object_loc = index_access.object.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 0 };

        // Check that index is an integer type
        const is_integer = switch (index_typed.resolved_type) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type => true,
            else => false,
        };
        if (!is_integer) {
            const got_str = try index_typed.resolved_type.toStr(self.allocator);
            defer self.allocator.free(got_str);
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "index must be an integer type, got {s}",
                    .{got_str},
                ),
                .{
                    .file = self.source_file,
                    .line = index_loc.line,
                    .column = index_loc.column,
                    .length = index_loc.length,
                },
                null,
            );
        }

        // Get element type from array/view
        // types are arena-managed, no clone needed
        const element_type = switch (object_typed.resolved_type) {
            .array => |arr| arr.element_type.*,
            .view => |view| view.element_type.*,
            else => blk: {
                const type_str = try object_typed.resolved_type.toStr(self.allocator);
                defer self.allocator.free(type_str);
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "cannot index into type {s}",
                        .{type_str},
                    ),
                    .{
                        .file = self.source_file,
                        .line = object_loc.line,
                        .column = object_loc.column,
                        .length = object_loc.length,
                    },
                    null,
                );
                // type is arena-managed, no cleanup needed;
                break :blk types.ResolvedType.unit_type;
            },
        };

        return element_type;
    }

    /// checks a variant constructor expression like `Just { value: 42 }` or `Nothing`
    fn checkVariantConstructor(self: *TypeChecker, variant_ctor: ast.VariantConstructorExpr) !types.ResolvedType {
        // search through type definitions to find a union type containing this variant
        var iter = self.symbols.global_scope.symbols.iterator();
        while (iter.next()) |entry| {
            const symbol = entry.value_ptr.*;
            if (symbol == .type_def) {
                const type_def = symbol.type_def;
                // check if this type is a union type with the matching variant
                if (type_def.underlying == .union_type) {
                    for (type_def.underlying.union_type.variants) |variant| {
                        if (std.mem.eql(u8, variant.name, variant_ctor.variant_name)) {
                            // found the union type containing this variant
                            // check field expressions if present
                            if (variant_ctor.fields) |fields| {
                                for (fields) |field| {
                                    var field_typed = try self.checkExpr(field.value);
                                    defer field_typed.deinit();

                                    // verify field exists in variant
                                    var field_found = false;
                                    for (variant.field_names, 0..) |vf_name, idx| {
                                        if (std.mem.eql(u8, vf_name, field.name)) {
                                            field_found = true;
                                            // check field type matches
                                            if (!field_typed.resolved_type.eql(&variant.field_types[idx])) {
                                                const expected_str = try variant.field_types[idx].toStr(self.allocator);
                                                defer self.allocator.free(expected_str);
                                                const got_str = try field_typed.resolved_type.toStr(self.allocator);
                                                defer self.allocator.free(got_str);
                                                try self.diagnostics_list.addError(
                                                    try std.fmt.allocPrint(
                                                        self.allocator,
                                                        "field '{s}' type mismatch: expected {s}, got {s}",
                                                        .{ field.name, expected_str, got_str },
                                                    ),
                                                    .{
                                                        .file = self.source_file,
                                                        .line = variant_ctor.name_loc.line,
                                                        .column = variant_ctor.name_loc.column,
                                                        .length = variant_ctor.variant_name.len,
                                                    },
                                                    null,
                                                );
                                            }
                                            break;
                                        }
                                    }
                                    if (!field_found) {
                                        try self.diagnostics_list.addError(
                                            try std.fmt.allocPrint(
                                                self.allocator,
                                                "variant '{s}' has no field named '{s}'",
                                                .{ variant_ctor.variant_name, field.name },
                                            ),
                                            .{
                                                .file = self.source_file,
                                                .line = variant_ctor.name_loc.line,
                                                .column = variant_ctor.name_loc.column,
                                                .length = variant_ctor.variant_name.len,
                                            },
                                            null,
                                        );
                                    }
                                }
                            }

                            // add hover info for the variant name
                            try self.hover_table.add(
                                variant_ctor.name_loc.line,
                                variant_ctor.name_loc.column,
                                variant_ctor.variant_name.len,
                                variant_ctor.variant_name,
                                .type_def,
                                type_def.underlying,
                            );

                            // return the named union type
                            // intern the type for arena management
                            const underlying_ptr = try self.allocator.create(types.ResolvedType);
                            underlying_ptr.* = type_def.underlying;
                            return try self.internType(types.ResolvedType{
                                .named = .{
                                    .name = type_def.name,
                                    .underlying = underlying_ptr,
                                },
                            });
                        }
                    }
                }
            }
        }

        // variant not found in any union type
        try self.diagnostics_list.addError(
            try std.fmt.allocPrint(
                self.allocator,
                "unknown variant '{s}' - not found in any union type",
                .{variant_ctor.variant_name},
            ),
            .{
                .file = self.source_file,
                .line = variant_ctor.name_loc.line,
                .column = variant_ctor.name_loc.column,
                .length = variant_ctor.variant_name.len,
            },
            null,
        );

        return types.ResolvedType.unit_type;
    }

    fn checkRecordLiteral(self: *TypeChecker, record_literal: ast.RecordLiteralExpr) !types.ResolvedType {
        // build arrays for field names, types, and locations
        const field_count = record_literal.fields.len;

        if (field_count == 0) {
            // empty record is unit type
            return types.ResolvedType.unit_type;
        }

        const field_names = try self.allocator.alloc([]const u8, field_count);
        var names_initialized: usize = 0;
        errdefer {
            for (field_names[0..names_initialized]) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(field_names);
        }

        const field_types = try self.allocator.alloc(types.ResolvedType, field_count);
        // types are arena-managed, only free the array on error
        errdefer self.allocator.free(field_types);

        const field_locations = try self.allocator.alloc(types.FieldLocation, field_count);
        errdefer self.allocator.free(field_locations);

        for (record_literal.fields, 0..) |field, i| {
            // duplicate field name so it's owned by this type
            field_names[i] = try self.allocator.dupe(u8, field.name);
            names_initialized += 1;

            const field_typed = try self.checkExpr(field.value);
            defer self.allocator.free(field_typed.effects);

            // types are arena-managed, store directly
            field_types[i] = field_typed.resolved_type;

            // store the field location
            field_locations[i] = .{
                .line = field.name_loc.line,
                .column = field.name_loc.column,
                .length = field.name.len,
            };
        }

        return types.ResolvedType{
            .record = .{
                .field_names = field_names,
                .field_types = field_types,
                .field_locations = field_locations,
            },
        };
    }

    fn checkRange(self: *TypeChecker, range_expr: ast.RangeExpr) !types.ResolvedType {
        var start_typed = try self.checkExpr(range_expr.start);
        defer self.allocator.free(start_typed.effects);

        var end_typed = try self.checkExpr(range_expr.end);
        defer self.allocator.free(end_typed.effects);

        if (!start_typed.resolved_type.eql(&end_typed.resolved_type)) {
            const start_str = try start_typed.resolved_type.toStr(self.allocator);
            defer self.allocator.free(start_str);
            const end_str = try end_typed.resolved_type.toStr(self.allocator);
            defer self.allocator.free(end_str);
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "range start and end must have same type: {s} vs {s}",
                    .{ start_str, end_str },
                ),
                .{ .file = self.source_file, .line = 0, .column = 0, .length = 0 },
                null,
            );
        }

        const elem_type_ptr = try self.allocator.create(types.ResolvedType);
        elem_type_ptr.* = start_typed.resolved_type;

        return types.ResolvedType{ .range = .{ .element_type = elem_type_ptr } };
    }

    fn checkMapError(self: *TypeChecker, map_error_expr: ast.MapErrorExpr) !types.ResolvedType {
        // get location from inner expression
        const loc = map_error_expr.expr.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 9 };

        // map_error requires an enclosing function with an error domain
        const current_domain = self.current_function_error_domain orelse {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'map_error' can only be used in functions with an error clause"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            const expr_typed = try self.checkExpr(map_error_expr.expr);
            defer self.allocator.free(expr_typed.effects);
            return expr_typed.resolved_type;
        };

        const expr_typed = try self.checkExpr(map_error_expr.expr);
        defer self.allocator.free(expr_typed.effects);

        // the expression must return a Result type
        if (expr_typed.resolved_type != .result) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'map_error' expression must return a Result type"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            return expr_typed.resolved_type;
        }

        const result_type = expr_typed.resolved_type.result;

        // type check the transform expression
        // the transform receives the error and should return a new error in the current domain
        var transform_typed = try self.checkExpr(map_error_expr.transform);
        defer transform_typed.deinit();

        // return Result<T, CurrentDomain> where T is the original ok type
        const ok_type_ptr = try self.allocator.create(types.ResolvedType);
        ok_type_ptr.* = result_type.ok_type.*;

        // intern the type for arena management
        return try self.internType(types.ResolvedType{
            .result = .{
                .ok_type = ok_type_ptr,
                .error_domain = current_domain,
            },
        });
    }

    fn checkAnonymousFunction(self: *TypeChecker, anon_func: ast.AnonymousFunctionExpr) !types.ResolvedType {
        // Resolve parameter types
        const params = try self.allocator.alloc(types.ResolvedType, anon_func.params.len);
        errdefer self.allocator.free(params);

        for (anon_func.params, 0..) |param, i| {
            params[i] = try self.type_resolver.resolve(param.type_annotation);
        }

        // Resolve return type
        const return_type_ptr = try self.allocator.create(types.ResolvedType);
        return_type_ptr.* = try self.type_resolver.resolve(anon_func.return_type);

        // Resolve effects
        const effects = try self.allocator.alloc(types.Effect, anon_func.effects.len);
        for (anon_func.effects, 0..) |effect_str, i| {
            if (types.Effect.fromString(effect_str)) |effect| {
                effects[i] = effect;
            }
        }

        return types.ResolvedType{
            .function_type = .{
                .params = params,
                .return_type = return_type_ptr,
                .effects = effects,
                .error_domain = anon_func.error_domain,
                .type_params = null,
            },
        };
    }

    fn checkUnsafeCast(self: *TypeChecker, unsafe_cast: ast.UnsafeCastExpr) !types.ResolvedType {
        // Type check the expression being cast
        var expr_typed = try self.checkExpr(unsafe_cast.expr);
        defer expr_typed.deinit();
        // Return the target type
        return try self.type_resolver.resolve(unsafe_cast.target_type);
    }

    fn checkComptimeExpr(self: *TypeChecker, comptime_expr: *ast.Expr) !types.ResolvedType {
        const expr_typed = try self.checkExpr(comptime_expr);
        defer self.allocator.free(expr_typed.effects);
        // resolved_type is returned directly; caller takes ownership (no deinit here)
        return expr_typed.resolved_type;
    }

    fn checkContextBlock(self: *TypeChecker, context_block: ast.ContextBlockExpr) !types.ResolvedType {
        // Type check each context item
        for (context_block.context_items) |item| {
            var item_typed = try self.checkExpr(item.value);
            defer item_typed.deinit();
        }
        // Type check body statements
        for (context_block.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
        return types.ResolvedType.unit_type;
    }

    fn checkBlockExpr(self: *TypeChecker, block_expr: ast.BlockExpr) !types.ResolvedType {
        // create a new scope for the block
        var block_scope = self.createScope(self.current_scope, self.current_scope.scope_level + 1);
        defer block_scope.deinit();

        const previous_scope = self.current_scope;
        self.current_scope = &block_scope;
        defer self.current_scope = previous_scope;

        // type check each statement in the block
        for (block_expr.statements) |stmt| {
            _ = try self.checkStmt(stmt);
        }

        // if there's a result expression, type check it and return its type
        if (block_expr.result_expr) |result| {
            const result_typed = try self.checkExpr(result);
            defer self.allocator.free(result_typed.effects);
            // types are arena-managed, return directly
            return result_typed.resolved_type;
        }

        // no result expression means the block returns unit
        return types.ResolvedType.unit_type;
    }

    fn checkFieldAccess(self: *TypeChecker, field_access: ast.FieldAccessExpr) !types.ResolvedType {
        const object_typed = try self.checkExpr(field_access.object);
        defer self.allocator.free(object_typed.effects);

        const field_name = field_access.field;
        const field_loc = field_access.field_loc;
        const object_type = object_typed.resolved_type;

        // handle field access based on object type
        switch (object_type) {
            .record => |rec| {
                // find the field in the record
                for (rec.field_names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, field_name)) {
                        // get field definition location if available
                        const field_def_loc: ?hover_info.FieldDefinitionLoc = if (rec.field_locations) |locs|
                            .{
                                .line = locs[i].line,
                                .column = locs[i].column,
                                .length = locs[i].length,
                            }
                        else
                            null;

                        // add hover info for field access with definition location
                        try self.hover_table.addWithFieldDef(
                            field_loc.line,
                            field_loc.column,
                            field_name.len,
                            field_name,
                            .field,
                            rec.field_types[i],
                            field_def_loc,
                        );

                        // types are arena-managed, return directly
                        return rec.field_types[i];
                    }
                }
                // field not found
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "record has no field '{s}'",
                        .{field_name},
                    ),
                    .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                    null,
                );
                // type is arena-managed, no cleanup needed;
                return types.ResolvedType.unit_type;
            },
            .result => |res| {
                // result type has special fields: tag, value, error_code
                if (std.mem.eql(u8, field_name, "tag")) {
                    // add hover info for Result.tag
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.i8,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.i8;
                } else if (std.mem.eql(u8, field_name, "value")) {
                    // add hover info for Result.value
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        res.ok_type.*,
                    );
                    // types are arena-managed, return directly
                    return res.ok_type.*;
                } else if (std.mem.eql(u8, field_name, "error_code")) {
                    // add hover info for Result.error_code
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.i64,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.i64;
                } else {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "Result type has no field '{s}' (available: tag, value, error_code)",
                            .{field_name},
                        ),
                        .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                        null,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.unit_type;
                }
            },
            .nullable => |inner| {
                // nullable type has special fields: has_value, value
                if (std.mem.eql(u8, field_name, "has_value")) {
                    // add hover info for nullable.has_value
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.bool_type,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.bool_type;
                } else if (std.mem.eql(u8, field_name, "value")) {
                    // add hover info for nullable.value
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        inner.*,
                    );
                    // types are arena-managed, return directly
                    return inner.*;
                } else {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "nullable type has no field '{s}' (available: has_value, value)",
                            .{field_name},
                        ),
                        .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                        null,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.unit_type;
                }
            },
            .string_type => {
                // string type has special fields: ptr, len
                if (std.mem.eql(u8, field_name, "len")) {
                    // add hover info for String.len
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.i64,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.i64;
                } else if (std.mem.eql(u8, field_name, "ptr")) {
                    // add hover info for String.ptr
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.usize_type,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.usize_type;
                } else {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "String has no field '{s}' (available: ptr, len)",
                            .{field_name},
                        ),
                        .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                        null,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.unit_type;
                }
            },
            .array => |arr| {
                // array has len field
                if (std.mem.eql(u8, field_name, "len")) {
                    // add hover info for array.len
                    try self.hover_table.add(
                        field_loc.line,
                        field_loc.column,
                        field_name.len,
                        field_name,
                        .field,
                        types.ResolvedType.usize_type,
                    );
                    _ = arr;
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.usize_type;
                } else {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "array has no field '{s}' (available: len)",
                            .{field_name},
                        ),
                        .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                        null,
                    );
                    // type is arena-managed, no cleanup needed;
                    return types.ResolvedType.unit_type;
                }
            },
            else => {
                const type_str = try object_type.toStr(self.allocator);
                defer self.allocator.free(type_str);
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "cannot access field '{s}' on type {s}",
                        .{ field_name, type_str },
                    ),
                    .{ .file = self.source_file, .line = field_loc.line, .column = field_loc.column, .length = field_name.len },
                    null,
                );
                // type is arena-managed, no cleanup needed;
                return types.ResolvedType.unit_type;
            },
        }
    }

    fn checkOk(self: *TypeChecker, ok_expr: *ast.Expr) !types.ResolvedType {
        // get location from inner expression
        const loc = ok_expr.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 2 };

        // ok requires an enclosing function with an error domain
        if (self.current_function_error_domain == null) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'ok' can only be used in functions with an error clause"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            // still type check the inner expression
            const inner_typed = try self.checkExpr(ok_expr);
            defer self.allocator.free(inner_typed.effects);
            return inner_typed.resolved_type;
        }

        const inner_typed = try self.checkExpr(ok_expr);
        defer self.allocator.free(inner_typed.effects);

        // return Result<T, E> where T is the inner type
        const ok_type_ptr = try self.allocator.create(types.ResolvedType);
        ok_type_ptr.* = inner_typed.resolved_type;

        return types.ResolvedType{
            .result = .{
                .ok_type = ok_type_ptr,
                .error_domain = self.current_function_error_domain.?,
            },
        };
    }

    fn checkErr(self: *TypeChecker, err_expr: ast.ErrorExpr) !types.ResolvedType {
        // err requires an enclosing function with an error domain
        const domain_name = self.current_function_error_domain orelse {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'err' can only be used in functions with an error clause"),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = err_expr.variant.len,
                },
                null,
            );
            return types.ResolvedType.unit_type;
        };

        // verify the variant exists in the domain
        if (self.domains) |domains| {
            if (domains.get(domain_name)) |domain| {
                if (domain.findVariant(err_expr.variant) == null) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "error variant '{s}' does not exist in domain '{s}'",
                            .{ err_expr.variant, domain_name },
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = err_expr.variant.len,
                        },
                        null,
                    );
                }
            }
        }

        // type check the field values
        for (err_expr.fields) |field| {
            var field_typed = try self.checkExpr(field.value);
            field_typed.deinit();
        }

        // return Result<Unit, E> - the ok type is Unit since err doesn't produce a value
        const ok_type_ptr = try self.allocator.create(types.ResolvedType);
        ok_type_ptr.* = types.ResolvedType.unit_type;

        return types.ResolvedType{
            .result = .{
                .ok_type = ok_type_ptr,
                .error_domain = domain_name,
            },
        };
    }

    fn checkCheck(self: *TypeChecker, check_expr: ast.CheckExpr) !types.ResolvedType {
        // get location from inner expression
        const loc = check_expr.expr.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 5 };

        // check requires an enclosing function with an error domain
        const current_domain = self.current_function_error_domain orelse {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'check' can only be used in functions with an error clause"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            // still type check the inner expression
            const expr_typed = try self.checkExpr(check_expr.expr);
            defer self.allocator.free(expr_typed.effects);
            return expr_typed.resolved_type;
        };

        const expr_typed = try self.checkExpr(check_expr.expr);
        defer self.allocator.free(expr_typed.effects);

        // the expression must return a Result type (checkCall now returns Result for error-domain functions)
        if (expr_typed.resolved_type != .result) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'check' expression must return a Result type"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            return expr_typed.resolved_type;
        }

        const result_type = expr_typed.resolved_type.result;

        // verify the error domain of the expression is a subset of the current function's domain
        if (self.domains) |domains| {
            const expr_domain_name = result_type.error_domain;
            if (!std.mem.eql(u8, expr_domain_name, current_domain)) {
                const is_subset = self.isDomainSubset(domains, expr_domain_name, current_domain);
                if (!is_subset) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "error domain '{s}' is not compatible with function's error domain '{s}'",
                            .{ expr_domain_name, current_domain },
                        ),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = loc.length,
                        },
                        null,
                    );
                }
            }
        }

        // type check context frame fields if present
        if (check_expr.context_frame) |frame| {
            for (frame) |field| {
                var field_typed = try self.checkExpr(field.value);
                field_typed.deinit();
            }
        }

        // return the unwrapped ok type
        // types are arena-managed, return directly
        return result_type.ok_type.*;
    }

    fn checkEnsure(self: *TypeChecker, ensure_expr: ast.EnsureExpr) !types.ResolvedType {
        // get location from condition expression
        const loc = ensure_expr.condition.getLocation() orelse ast.Location{ .line = 0, .column = 0, .length = 6 };

        // ensure requires an enclosing function with an error domain
        const domain_name = self.current_function_error_domain orelse {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "'ensure' can only be used in functions with an error clause"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
            // still type check the condition
            var condition_typed = try self.checkExpr(ensure_expr.condition);
            condition_typed.deinit();
            return types.ResolvedType.unit_type;
        };

        var condition_typed = try self.checkExpr(ensure_expr.condition);
        defer condition_typed.deinit();

        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "ensure condition must be Bool"),
                .{
                    .file = self.source_file,
                    .line = loc.line,
                    .column = loc.column,
                    .length = loc.length,
                },
                null,
            );
        }

        // verify the error variant exists in the domain
        if (self.domains) |domains| {
            if (domains.get(domain_name)) |domain| {
                if (domain.findVariant(ensure_expr.error_expr.variant) == null) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "error variant '{s}' does not exist in domain '{s}'",
                            .{ ensure_expr.error_expr.variant, domain_name },
                        ),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = ensure_expr.error_expr.variant.len,
                        },
                        null,
                    );
                }
            }
        }

        // type check the error field values
        for (ensure_expr.error_expr.fields) |field| {
            var field_typed = try self.checkExpr(field.value);
            field_typed.deinit();
        }

        // ensure returns Unit on success (the error path returns from function)
        return types.ResolvedType.unit_type;
    }

    /// check if domain_a is a subset of domain_b (all variants in a exist in b)
    fn isDomainSubset(self: *TypeChecker, domains: *error_domains.ErrorDomainTable, domain_a: []const u8, domain_b: []const u8) bool {
        _ = self;
        const a = domains.get(domain_a) orelse return false;
        const b = domains.get(domain_b) orelse return false;

        // every variant in a must exist in b
        for (a.variants) |variant_a| {
            var found = false;
            for (b.variants) |variant_b| {
                if (std.mem.eql(u8, variant_a.name, variant_b.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    fn checkMatchExpr(self: *TypeChecker, match_expr: ast.MatchExpr) !types.ResolvedType {
        const value_typed = try self.checkExpr(match_expr.value);
        defer {
            self.allocator.free(value_typed.effects);
        }

        // types are arena-managed, no clone needed
        const match_type = value_typed.resolved_type;

        var result_type: ?types.ResolvedType = null;
        for (match_expr.arms) |arm| {
            // validate pattern against the matched value type
            try self.checkPattern(arm.pattern, match_type);

            // create a new scope for each arm to bind pattern variables
            var arm_scope = self.createScope(self.current_scope, self.current_scope.scope_level + 1);
            defer arm_scope.deinit();

            const prev_scope = self.current_scope;
            defer self.current_scope = prev_scope;
            self.current_scope = &arm_scope;

            // bind pattern variables to the arm scope
            try self.bindPatternVariables(arm.pattern, match_type);

            var arm_typed = try self.checkExpr(arm.body);
            if (result_type) |rt| {
                defer arm_typed.deinit();
                if (!rt.eql(&arm_typed.resolved_type)) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "match arms must have the same type"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
            } else {
                defer self.allocator.free(arm_typed.effects);
                result_type = arm_typed.resolved_type;
            }
        }

        return result_type orelse types.ResolvedType.unit_type;
    }

    fn checkArrayLiteral(self: *TypeChecker, array_literal: ast.ArrayLiteralExpr) !types.ResolvedType {
        if (array_literal.elements.len == 0) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "cannot infer type of empty array literal"),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                null,
            );
            return types.ResolvedType.unit_type;
        }

        const first_elem_typed = try self.checkExpr(array_literal.elements[0]);
        defer self.allocator.free(first_elem_typed.effects);
        const element_type = first_elem_typed.resolved_type;

        for (array_literal.elements[1..]) |elem| {
            var elem_typed = try self.checkExpr(elem);
            defer elem_typed.deinit();
            if (!elem_typed.resolved_type.eql(&element_type)) {
                const expected_str = try element_type.toStr(self.allocator);
                defer self.allocator.free(expected_str);
                const got_str = try elem_typed.resolved_type.toStr(self.allocator);
                defer self.allocator.free(got_str);
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "array elements must have the same type: expected {s}, got {s}",
                        .{ expected_str, got_str },
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
            }
        }

        const elem_type_ptr = try self.allocator.create(types.ResolvedType);
        elem_type_ptr.* = element_type;

        // intern the type for arena management
        return try self.internType(types.ResolvedType{
            .array = .{
                .element_type = elem_type_ptr,
                .size = array_literal.elements.len,
            },
        });
    }

    fn isNumericLiteral(self: *TypeChecker, expr: *ast.Expr) bool {
        _ = self;
        return expr.* == .number;
    }

    fn canUnifyNumericLiteral(self: *TypeChecker, expr: *ast.Expr, inferred: *const types.ResolvedType, declared: *const types.ResolvedType) bool {
        // if the expression is a numeric literal, allow it to unify with any numeric type
        if (expr.* == .number) {
            return self.isNumericType(inferred) and self.isNumericType(declared);
        }

        // if the expression is an array literal with all numeric elements, allow unification
        // with an array of a compatible numeric type
        if (expr.* == .array_literal) {
            const array_lit = expr.array_literal;

            // check that both types are arrays with the same size
            if (inferred.* != .array or declared.* != .array) {
                return false;
            }

            if (inferred.array.size != declared.array.size) {
                return false;
            }

            // check that both element types are numeric
            if (!self.isNumericType(inferred.array.element_type) or !self.isNumericType(declared.array.element_type)) {
                return false;
            }

            // check that all elements are numeric literals
            for (array_lit.elements) |elem| {
                if (!self.isNumericLiteral(elem)) {
                    return false;
                }
            }

            return true;
        }

        return false;
    }

    fn isNumericType(self: *TypeChecker, t: *const types.ResolvedType) bool {
        _ = self;
        return switch (t.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64 => true,
            else => false,
        };
    }
};

test {
    _ = @import("type_checker_test.zig");
}
