const std = @import("std");
const type_checker = @import("type_checker.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const types = @import("../types.zig");

test "check simple number literal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var expr = ast.Expr{ .number = "42" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.i32, typed.resolved_type);
}

test "check float literal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var expr = ast.Expr{ .number = "3.14" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.f64, typed.resolved_type);
}

test "check string literal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var expr = ast.Expr{ .string = "hello" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.string_type, typed.resolved_type);
}

test "check bool literal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var expr = ast.Expr{ .bool_literal = true };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.bool_type, typed.resolved_type);
}

test "check undefined identifier should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var expr = ast.Expr{ .identifier = "undefined_var" };
    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "check variable declaration with matching types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .number = "42" };

    const var_decl = ast.VarDecl{
        .name = "x",
        .type_annotation = .{ .simple = "i32" },
        .value = &value,
    };

    try checker.checkVarDecl(var_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "check binary addition of same types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{
        .binary = .{
            .left = &left,
            .op = .add,
            .right = &right,
        },
    };

    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.i32, typed.resolved_type);
    try std.testing.expect(!diag_list.hasErrors());
}

test "check binary comparison returns bool" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{
        .binary = .{
            .left = &left,
            .op = .lt,
            .right = &right,
        },
    };

    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.bool_type, typed.resolved_type);
}

test "check logical operators require bool operands" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{
        .binary = .{
            .left = &left,
            .op = .logical_and,
            .right = &right,
        },
    };

    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "check if statement with non-bool condition should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var condition = ast.Expr{ .number = "42" };

    const if_stmt = ast.IfStmt{
        .condition = &condition,
        .then_block = &[_]ast.Stmt{},
        .else_block = null,
    };

    try checker.checkIfStmt(if_stmt);

    try std.testing.expect(diag_list.hasErrors());
}

test "check while statement with non-bool condition should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var condition = ast.Expr{ .string = "not bool" };

    const while_stmt = ast.WhileStmt{
        .condition = &condition,
        .body = &[_]ast.Stmt{},
    };

    try checker.checkWhileStmt(while_stmt);

    try std.testing.expect(diag_list.hasErrors());
}

test "check function call with wrong argument count should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const params = try allocator.alloc(types.ResolvedType, 2);
    defer allocator.free(params);
    params[0] = .i32;
    params[1] = .i32;

    var is_cap_params = [_]bool{ false, false };
    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .params = params,
            .return_type = .unit_type,
            .effects = &[_]types.Effect{},
            .error_domain = null,
            .is_capability_param = is_cap_params[0..],
        },
    };

    try symbols.insertGlobal("test_func", func_symbol);

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var callee = ast.Expr{ .identifier = "test_func" };
    var expr = ast.Expr{
        .call = .{
            .callee = &callee,
            .args = &[_]*ast.Expr{},
        },
    };

    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "check assignment to immutable variable should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const const_symbol = symbol_table.Symbol{
        .variable = .{
            .name = "x",
            .type_annotation = .i32,
            .is_mutable = false,
            .scope_level = 0,
        },
    };

    try checker.current_scope.insert("x", const_symbol);

    var value = ast.Expr{ .number = "42" };

    const assign = ast.AssignStmt{
        .target = "x",
        .value = &value,
    };

    try checker.checkAssignStmt(assign);

    try std.testing.expect(diag_list.hasErrors());
}

test "check return type mismatch should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var func_symbol = symbol_table.FunctionSymbol{
        .name = "test",
        .params = &[_]types.ResolvedType{},
        .return_type = .i32,
        .effects = &[_]types.Effect{},
        .error_domain = null,
        .is_capability_param = &[_]bool{},
    };

    checker.current_function = &func_symbol;

    var return_value = ast.Expr{ .string = "wrong type" };

    try checker.checkReturnStmt(&return_value);

    try std.testing.expect(diag_list.hasErrors());
}

test "check ensure with non-bool condition should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var condition = ast.Expr{ .number = "42" };
    var expr = ast.Expr{
        .ensure = .{
            .condition = &condition,
            .error_expr = .{
                .variant = "Error",
                .fields = &[_]ast.Field{},
            },
        },
    };

    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "check match arms with different types should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = type_checker.TypeChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .identifier = "x" };
    var body1 = ast.Expr{ .number = "1" };
    var body2 = ast.Expr{ .string = "hello" };

    var match_arms = [_]ast.MatchArm{
        .{
            .pattern = .{ .number = "1" },
            .body = &body1,
        },
        .{
            .pattern = .{ .number = "2" },
            .body = &body2,
        },
    };
    var expr = ast.Expr{
        .match_expr = .{
            .value = &value,
            .arms = match_arms[0..],
        },
    };

    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}
