const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const typed_ast = @import("../typed_ast.zig");
const type_resolver = @import("type_resolver.zig");

pub const TypeChecker = struct {
    symbols: *symbol_table.SymbolTable,
    current_scope: *symbol_table.Scope,
    current_function: ?*symbol_table.FunctionSymbol,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    type_resolver: type_resolver.TypeResolver,

    pub fn init(
        allocator: std.mem.Allocator,
        symbols: *symbol_table.SymbolTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) TypeChecker {
        return .{
            .symbols = symbols,
            .current_scope = &symbols.global_scope,
            .current_function = null,
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
            .type_resolver = type_resolver.TypeResolver.init(allocator, symbols, diagnostics_list, source_file),
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

        if (const_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            if (!declared_type.eql(&value_typed.resolved_type)) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "type mismatch in constant declaration: expected {any}, got {any}",
                        .{ declared_type, value_typed.resolved_type },
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = const_decl.name.len,
                    },
                    null,
                );
            }
        }

        const const_symbol = symbol_table.Symbol{
            .constant = .{
                .name = const_decl.name,
                .type_annotation = value_typed.resolved_type,
                .scope_level = self.current_scope.scope_level,
            },
        };

        try self.current_scope.insert(const_decl.name, const_symbol);
    }

    pub fn checkVarDecl(self: *TypeChecker, var_decl: ast.VarDecl) !void {
        const value_typed = try self.checkExpr(var_decl.value);

        if (var_decl.type_annotation) |type_annotation| {
            const declared_type = try self.type_resolver.resolve(type_annotation);
            if (!declared_type.eql(&value_typed.resolved_type)) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "type mismatch in variable declaration: expected {any}, got {any}",
                        .{ declared_type, value_typed.resolved_type },
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = var_decl.name.len,
                    },
                    null,
                );
            }
        }

        const var_symbol = symbol_table.Symbol{
            .variable = .{
                .name = var_decl.name,
                .type_annotation = value_typed.resolved_type,
                .is_mutable = true,
                .scope_level = self.current_scope.scope_level,
            },
        };

        try self.current_scope.insert(var_decl.name, var_symbol);
    }

    pub fn checkReturnStmt(self: *TypeChecker, return_stmt: ast.ReturnStmt) !void {
        if (self.current_function) |func| {
            if (return_stmt.value) |expr| {
                const expr_typed = try self.checkExpr(expr);
                if (!func.return_type.eql(&expr_typed.resolved_type)) {
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
        _ = try self.checkExpr(expr);
    }

    pub fn checkAssignStmt(self: *TypeChecker, assign: ast.AssignStmt) !void {
        const value_typed = try self.checkExpr(assign.value);

        if (self.current_scope.lookup(assign.target)) |symbol| {
            switch (symbol) {
                .variable => |v| {
                    if (!v.is_mutable) {
                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "cannot assign to immutable variable '{s}'",
                                .{assign.target},
                            ),
                            .{
                                .file = self.source_file,
                                .line = 0,
                                .column = 0,
                                .length = assign.target.len,
                            },
                            null,
                        );
                    }
                    if (!v.type_annotation.eql(&value_typed.resolved_type)) {
                        try self.diagnostics_list.addError(
                            try std.fmt.allocPrint(
                                self.allocator,
                                "type mismatch in assignment: expected {any}, got {any}",
                                .{ v.type_annotation, value_typed.resolved_type },
                            ),
                            .{
                                .file = self.source_file,
                                .line = 0,
                                .column = 0,
                                .length = assign.target.len,
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
                            .{assign.target},
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = assign.target.len,
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
                    .{assign.target},
                ),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = assign.target.len,
                },
                null,
            );
        }
    }

    pub fn checkIfStmt(self: *TypeChecker, if_stmt: ast.IfStmt) !void {
        const condition_typed = try self.checkExpr(if_stmt.condition);
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
        _ = iterable_typed;

        var new_scope = symbol_table.Scope.init(self.allocator, self.current_scope, self.current_scope.scope_level + 1);
        defer new_scope.deinit();

        const prev_scope = self.current_scope;
        defer self.current_scope = prev_scope;
        self.current_scope = &new_scope;

        for (for_stmt.body) |stmt| {
            _ = try self.checkStmt(stmt);
        }
    }

    fn checkMatchStmt(self: *TypeChecker, match_stmt: ast.MatchStmt) !void {
        const value_typed = try self.checkExpr(match_stmt.value);
        _ = value_typed;

        for (match_stmt.arms) |arm| {
            _ = try self.checkExpr(arm.body);
        }
    }

    pub fn checkExpr(self: *TypeChecker, expr: *ast.Expr) std.mem.Allocator.Error!typed_ast.TypedExpr {
        const resolved_type = switch (expr.*) {
            .number => try self.inferNumberType(expr.number),
            .string => types.ResolvedType.string_type,
            .char => types.ResolvedType.char_type,
            .bool_literal => types.ResolvedType.bool_type,
            .null_literal => types.ResolvedType.unit_type,
            .identifier => |id| try self.checkIdentifier(id),
            .binary => |be| try self.checkBinary(be),
            .unary => |ue| try self.checkUnary(ue),
            .call => |ce| try self.checkCall(ce),
            .field_access => |fa| try self.checkFieldAccess(fa),
            .ok => |ok_expr| try self.checkOk(ok_expr),
            .err => |ee| try self.checkErr(ee),
            .check => |ce| try self.checkCheck(ce),
            .ensure => |ee| try self.checkEnsure(ee),
            .match_expr => |me| try self.checkMatchExpr(me),
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

    fn checkIdentifier(self: *TypeChecker, id: []const u8) !types.ResolvedType {
        if (self.current_scope.lookup(id)) |symbol| {
            return switch (symbol) {
                .variable => |v| v.type_annotation,
                .constant => |c| c.type_annotation,
                .parameter => |p| p.type_annotation,
                .function => types.ResolvedType.unit_type,
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
        }

        try self.diagnostics_list.addError(
            try std.fmt.allocPrint(
                self.allocator,
                "undefined identifier '{s}'",
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
    }

    fn checkBinary(self: *TypeChecker, binary: ast.BinaryExpr) !types.ResolvedType {
        const left_typed = try self.checkExpr(binary.left);
        const right_typed = try self.checkExpr(binary.right);

        switch (binary.op) {
            .add, .subtract, .multiply, .divide, .modulo => {
                if (!left_typed.resolved_type.eql(&right_typed.resolved_type)) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in binary operation: {any} and {any}",
                            .{ left_typed.resolved_type, right_typed.resolved_type },
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
                return left_typed.resolved_type;
            },
            .eq, .ne, .lt, .gt, .le, .ge => {
                if (!left_typed.resolved_type.eql(&right_typed.resolved_type)) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "type mismatch in comparison: {any} and {any}",
                            .{ left_typed.resolved_type, right_typed.resolved_type },
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
                return types.ResolvedType.bool_type;
            },
            .logical_and, .logical_or => {
                if (left_typed.resolved_type != .bool_type or right_typed.resolved_type != .bool_type) {
                    try self.diagnostics_list.addError(
                        try self.allocator.dupe(u8, "logical operators require Bool operands"),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        null,
                    );
                }
                return types.ResolvedType.bool_type;
            },
            else => return left_typed.resolved_type,
        }
    }

    fn checkUnary(self: *TypeChecker, unary: ast.UnaryExpr) !types.ResolvedType {
        const operand_typed = try self.checkExpr(unary.operand);
        return operand_typed.resolved_type;
    }

    fn checkCall(self: *TypeChecker, call: ast.CallExpr) !types.ResolvedType {
        if (call.callee.* == .identifier) {
            const func_name = call.callee.identifier;
            if (self.symbols.lookupGlobal(func_name)) |symbol| {
                if (symbol == .function) {
                    const func = symbol.function;

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
                    } else {
                        for (call.args, func.params, 0..) |arg, param_type, i| {
                            const arg_typed = try self.checkExpr(arg);
                            if (!arg_typed.resolved_type.eql(&param_type)) {
                                try self.diagnostics_list.addError(
                                    try std.fmt.allocPrint(
                                        self.allocator,
                                        "argument {d} type mismatch: expected {any}, got {any}",
                                        .{ i, param_type, arg_typed.resolved_type },
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

                    return func.return_type;
                }
            }
        }

        return types.ResolvedType.unit_type;
    }

    fn checkFieldAccess(self: *TypeChecker, field_access: ast.FieldAccessExpr) !types.ResolvedType {
        const object_typed = try self.checkExpr(field_access.object);
        _ = object_typed;
        _ = field_access.field;
        return types.ResolvedType.unit_type;
    }

    fn checkOk(self: *TypeChecker, ok_expr: *ast.Expr) !types.ResolvedType {
        const inner_typed = try self.checkExpr(ok_expr);
        return inner_typed.resolved_type;
    }

    fn checkErr(self: *TypeChecker, err_expr: ast.ErrorExpr) !types.ResolvedType {
        _ = self;
        _ = err_expr;
        return types.ResolvedType.unit_type;
    }

    fn checkCheck(self: *TypeChecker, check_expr: ast.CheckExpr) !types.ResolvedType {
        const expr_typed = try self.checkExpr(check_expr.expr);
        return expr_typed.resolved_type;
    }

    fn checkEnsure(self: *TypeChecker, ensure_expr: ast.EnsureExpr) !types.ResolvedType {
        const condition_typed = try self.checkExpr(ensure_expr.condition);
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
        _ = value_typed;

        var result_type: ?types.ResolvedType = null;
        for (match_expr.arms) |arm| {
            const arm_typed = try self.checkExpr(arm.body);
            if (result_type) |rt| {
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
                result_type = arm_typed.resolved_type;
            }
        }

        return result_type orelse types.ResolvedType.unit_type;
    }
};

test {
    _ = @import("type_checker_test.zig");
}
