const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const typed_ast = @import("../typed_ast.zig");
const type_resolver = @import("type_resolver.zig");
const hover_info = @import("../hover_info.zig");
const symbol_locations = @import("../symbol_locations.zig");

pub const TypeChecker = struct {
    symbols: *symbol_table.SymbolTable,
    current_scope: *symbol_table.Scope,
    current_function: ?*symbol_table.FunctionSymbol,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    type_resolver: type_resolver.TypeResolver,
    hover_table: *hover_info.HoverInfoTable,
    location_table: *symbol_locations.SymbolLocationTable,

    pub fn init(
        allocator: std.mem.Allocator,
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
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
            .type_resolver = type_resolver.TypeResolver.init(allocator, symbols, diagnostics_list, source_file),
            .hover_table = hover_table,
            .location_table = location_table,
        };
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
        var new_scope = symbol_table.Scope.init(self.allocator, self.current_scope, self.current_scope.scope_level + 1);
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
                    const param_symbol = symbol_table.Symbol{
                        .parameter = .{
                            .name = param.name,
                            .type_annotation = param_type,
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
    }

    fn checkConstDecl(self: *TypeChecker, const_decl: ast.ConstDecl) !void {
        const value_typed = try self.checkExpr(const_decl.value);
        defer {
            // only deinit effects array, not the resolved_type since it's transferred to final_type
            self.allocator.free(value_typed.effects);
        }

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
        var should_deinit_value_type = false;

        if (const_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            should_deinit_value_type = true;
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

        if (should_deinit_value_type) {
            value_typed.resolved_type.deinit(self.allocator);
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
        var should_deinit_value_type = false;

        if (var_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            should_deinit_value_type = true;
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

        if (should_deinit_value_type) {
            value_typed.resolved_type.deinit(self.allocator);
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
                const expr_typed = try self.checkExpr(expr);
                defer {
                    expr_typed.resolved_type.deinit(self.allocator);
                    self.allocator.free(expr_typed.effects);
                }

                // allow numeric literals to unify with the expected return type
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
        const typed_expr = try self.checkExpr(expr);
        typed_expr.resolved_type.deinit(self.allocator);
        self.allocator.free(typed_expr.effects);
    }

    pub fn checkAssignStmt(self: *TypeChecker, assign: ast.AssignStmt) !void {
        const value_typed = try self.checkExpr(assign.value);
        defer {
            value_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(value_typed.effects);
        }

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
        const condition_typed = try self.checkExpr(if_stmt.condition);
        defer {
            condition_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(condition_typed.effects);
        }
        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "if condition must be Bool, got {any}",
                    .{condition_typed.resolved_type},
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
        const condition_typed = try self.checkExpr(while_stmt.condition);
        defer {
            condition_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(condition_typed.effects);
        }
        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try std.fmt.allocPrint(
                    self.allocator,
                    "while condition must be Bool, got {any}",
                    .{condition_typed.resolved_type},
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

        for (while_stmt.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
    }

    fn checkForStmt(self: *TypeChecker, for_stmt: ast.ForStmt) !void {
        const iterable_typed = try self.checkExpr(for_stmt.iterable);
        defer {
            self.allocator.free(iterable_typed.effects);
        }

        var new_scope = symbol_table.Scope.init(self.allocator, self.current_scope, self.current_scope.scope_level + 1);
        defer new_scope.deinit();

        const prev_scope = self.current_scope;
        defer self.current_scope = prev_scope;
        self.current_scope = &new_scope;

        const element_type = switch (iterable_typed.resolved_type) {
            .array => |arr| try arr.element_type.clone(self.allocator),
            .view => |view| try view.element_type.clone(self.allocator),
            .range => |r| try r.element_type.clone(self.allocator),
            else => types.ResolvedType.unit_type,
        };
        defer iterable_typed.resolved_type.deinit(self.allocator);

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
        const value_typed = try self.checkExpr(match_stmt.value);
        defer {
            value_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(value_typed.effects);
        }

        for (match_stmt.arms) |arm| {
            const arm_typed = try self.checkExpr(arm.body);
            defer {
                arm_typed.resolved_type.deinit(self.allocator);
                self.allocator.free(arm_typed.effects);
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
        };

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
                            .line = 0,
                            .column = 0,
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

            // clone the type so callers can safely deinit without affecting the symbol table
            return try resolved_type.clone(self.allocator);
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
        const left_typed = try self.checkExpr(binary.left);
        defer self.allocator.free(left_typed.effects);
        const right_typed = try self.checkExpr(binary.right);
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
                    left_typed.resolved_type.deinit(self.allocator);
                    return right_typed.resolved_type;
                }
                if (self.isNumericLiteral(binary.right) and self.isNumericType(&left_typed.resolved_type)) {
                    right_typed.resolved_type.deinit(self.allocator);
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
                    left_typed.resolved_type.deinit(self.allocator);
                    right_typed.resolved_type.deinit(self.allocator);
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
                right_typed.resolved_type.deinit(self.allocator);
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
                left_typed.resolved_type.deinit(self.allocator);
                right_typed.resolved_type.deinit(self.allocator);
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
                left_typed.resolved_type.deinit(self.allocator);
                right_typed.resolved_type.deinit(self.allocator);
                return types.ResolvedType.bool_type;
            },
            else => {
                right_typed.resolved_type.deinit(self.allocator);
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
                                .line = 0,
                                .column = 0,
                                .length = func_name.len,
                            },
                            null,
                        );
                        return types.ResolvedType.unit_type;
                    }

                    // check if this is a generic function
                    if (func.type_params) |type_params| {
                        // collect argument types for inference
                        var arg_types = try self.allocator.alloc(types.ResolvedType, call.args.len);
                        defer {
                            for (arg_types) |*at| {
                                at.deinit(self.allocator);
                            }
                            self.allocator.free(arg_types);
                        }

                        for (call.args, 0..) |arg, i| {
                            const arg_typed = try self.checkExpr(arg);
                            defer self.allocator.free(arg_typed.effects);
                            arg_types[i] = arg_typed.resolved_type;
                        }

                        // infer type arguments from argument types
                        const inferred = try self.inferTypeArgs(type_params, func.params, arg_types);
                        if (inferred) |inferred_args| {
                            defer {
                                for (inferred_args) |*ia| {
                                    ia.deinit(self.allocator);
                                }
                                self.allocator.free(inferred_args);
                            }

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
                        const arg_typed = try self.checkExpr(arg);
                        defer {
                            arg_typed.resolved_type.deinit(self.allocator);
                            self.allocator.free(arg_typed.effects);
                        }

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
        for (inferred_flags, 0..) |flag, i| {
            if (!flag) {
                // free already inferred types
                for (inferred[0..i]) |*inf| {
                    inf.deinit(self.allocator);
                }
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
                            inferred[i] = try arg_type.clone(self.allocator);
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
        const object_typed = try self.checkExpr(index_access.object);
        defer {
            self.allocator.free(object_typed.effects);
        }
        const index_typed = try self.checkExpr(index_access.index);
        defer {
            index_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(index_typed.effects);
        }

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
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                null,
            );
        }

        // Get element type from array/view
        const element_type = switch (object_typed.resolved_type) {
            .array => |arr| blk: {
                const elem = try arr.element_type.clone(self.allocator);
                object_typed.resolved_type.deinit(self.allocator);
                break :blk elem;
            },
            .view => |view| blk: {
                const elem = try view.element_type.clone(self.allocator);
                object_typed.resolved_type.deinit(self.allocator);
                break :blk elem;
            },
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
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
                object_typed.resolved_type.deinit(self.allocator);
                break :blk types.ResolvedType.unit_type;
            },
        };

        return element_type;
    }

    fn checkRecordLiteral(self: *TypeChecker, record_literal: ast.RecordLiteralExpr) !types.ResolvedType {
        for (record_literal.fields) |field| {
            const field_typed = try self.checkExpr(field.value);
            defer {
                field_typed.resolved_type.deinit(self.allocator);
                self.allocator.free(field_typed.effects);
            }
        }
        return types.ResolvedType.unit_type;
    }

    fn checkRange(self: *TypeChecker, range_expr: ast.RangeExpr) !types.ResolvedType {
        const start_typed = try self.checkExpr(range_expr.start);
        defer self.allocator.free(start_typed.effects);

        const end_typed = try self.checkExpr(range_expr.end);
        defer {
            end_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(end_typed.effects);
        }

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
        const expr_typed = try self.checkExpr(map_error_expr.expr);
        defer {
            self.allocator.free(expr_typed.effects);
        }
        const transform_typed = try self.checkExpr(map_error_expr.transform);
        defer {
            transform_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(transform_typed.effects);
        }
        // Return the type of the original expression (the ok type)
        return expr_typed.resolved_type;
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
        const expr_typed = try self.checkExpr(unsafe_cast.expr);
        defer {
            expr_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(expr_typed.effects);
        }
        // Return the target type
        return try self.type_resolver.resolve(unsafe_cast.target_type);
    }

    fn checkComptimeExpr(self: *TypeChecker, comptime_expr: *ast.Expr) !types.ResolvedType {
        const expr_typed = try self.checkExpr(comptime_expr);
        defer {
            self.allocator.free(expr_typed.effects);
        }
        return expr_typed.resolved_type;
    }

    fn checkContextBlock(self: *TypeChecker, context_block: ast.ContextBlockExpr) !types.ResolvedType {
        // Type check each context item
        for (context_block.context_items) |item| {
            const item_typed = try self.checkExpr(item.value);
            defer {
                item_typed.resolved_type.deinit(self.allocator);
                self.allocator.free(item_typed.effects);
            }
        }
        // Type check body statements
        for (context_block.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
        return types.ResolvedType.unit_type;
    }

    fn checkFieldAccess(self: *TypeChecker, field_access: ast.FieldAccessExpr) !types.ResolvedType {
        const object_typed = try self.checkExpr(field_access.object);
        defer {
            object_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(object_typed.effects);
        }
        _ = field_access.field;
        return types.ResolvedType.unit_type;
    }

    fn checkOk(self: *TypeChecker, ok_expr: *ast.Expr) !types.ResolvedType {
        const inner_typed = try self.checkExpr(ok_expr);
        defer self.allocator.free(inner_typed.effects);
        return inner_typed.resolved_type;
    }

    fn checkErr(self: *TypeChecker, err_expr: ast.ErrorExpr) !types.ResolvedType {
        _ = self;
        _ = err_expr;
        return types.ResolvedType.unit_type;
    }

    fn checkCheck(self: *TypeChecker, check_expr: ast.CheckExpr) !types.ResolvedType {
        const expr_typed = try self.checkExpr(check_expr.expr);
        defer self.allocator.free(expr_typed.effects);
        return expr_typed.resolved_type;
    }

    fn checkEnsure(self: *TypeChecker, ensure_expr: ast.EnsureExpr) !types.ResolvedType {
        const condition_typed = try self.checkExpr(ensure_expr.condition);
        defer {
            condition_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(condition_typed.effects);
        }
        if (condition_typed.resolved_type != .bool_type) {
            try self.diagnostics_list.addError(
                try self.allocator.dupe(u8, "ensure condition must be Bool"),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                null,
            );
        }
        return types.ResolvedType.unit_type;
    }

    fn checkMatchExpr(self: *TypeChecker, match_expr: ast.MatchExpr) !types.ResolvedType {
        const value_typed = try self.checkExpr(match_expr.value);
        defer {
            value_typed.resolved_type.deinit(self.allocator);
            self.allocator.free(value_typed.effects);
        }

        var result_type: ?types.ResolvedType = null;
        for (match_expr.arms) |arm| {
            const arm_typed = try self.checkExpr(arm.body);
            if (result_type) |rt| {
                defer {
                    arm_typed.resolved_type.deinit(self.allocator);
                    self.allocator.free(arm_typed.effects);
                }
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
        defer {
            self.allocator.free(first_elem_typed.effects);
        }
        const element_type = first_elem_typed.resolved_type;

        for (array_literal.elements[1..]) |elem| {
            const elem_typed = try self.checkExpr(elem);
            defer {
                elem_typed.resolved_type.deinit(self.allocator);
                self.allocator.free(elem_typed.effects);
            }
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
        elem_type_ptr.* = try element_type.clone(self.allocator);

        return types.ResolvedType{
            .array = .{
                .element_type = elem_type_ptr,
                .size = array_literal.elements.len,
            },
        };
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
