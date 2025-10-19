const std = @import("std");
const error_checker = @import("error_checker.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");

test "function with valid error domain should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "FileError",
        .effects = &[_][]const u8{},
        .body = &[_]ast.Stmt{},
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "function with unknown error domain should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "UnknownDomain",
        .effects = &[_][]const u8{},
        .body = &[_]ast.Stmt{},
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "valid error variant in function body should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var err_expr = ast.Expr{
        .err = .{
            .variant = "NotFound",
            .fields = &[_]ast.Field{},
        },
    };

    var body_stmts1 = [_]ast.Stmt{
        .{ .expr_stmt = &err_expr },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "FileError",
        .effects = &[_][]const u8{},
        .body = body_stmts1[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "invalid error variant should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var err_expr = ast.Expr{
        .err = .{
            .variant = "InvalidVariant",
            .fields = &[_]ast.Field{},
        },
    };

    var body_stmts2 = [_]ast.Stmt{
        .{ .expr_stmt = &err_expr },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "FileError",
        .effects = &[_][]const u8{},
        .body = body_stmts2[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "check expression with valid error should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var inner_expr = ast.Expr{ .identifier = "result" };
    var check_expr = ast.Expr{
        .check = .{
            .expr = &inner_expr,
            .context_frame = null,
        },
    };

    var body_stmts3 = [_]ast.Stmt{
        .{ .expr_stmt = &check_expr },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "FileError",
        .effects = &[_][]const u8{},
        .body = body_stmts3[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "ensure expression with valid error should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "ValidationFailed",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "ValidationError",
        .variants = variants,
    };

    try domains.insert("ValidationError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var condition_expr = ast.Expr{ .bool_literal = true };
    var ensure_expr = ast.Expr{
        .ensure = .{
            .condition = &condition_expr,
            .error_expr = .{
                .variant = "ValidationFailed",
                .fields = &[_]ast.Field{},
            },
        },
    };

    var body_stmts4 = [_]ast.Stmt{
        .{ .expr_stmt = &ensure_expr },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "ValidationError",
        .effects = &[_][]const u8{},
        .body = body_stmts4[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "errors in nested if statement should be checked" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 1);
    variants[0] = .{
        .name = "Valid",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "TestError",
        .variants = variants,
    };

    try domains.insert("TestError", domain);

    var checker = error_checker.ErrorChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var condition = ast.Expr{ .bool_literal = true };
    var err_expr = ast.Expr{
        .err = .{
            .variant = "InvalidVariant",
            .fields = &[_]ast.Field{},
        },
    };

    var then_stmts = [_]ast.Stmt{
        .{ .expr_stmt = &err_expr },
    };
    const if_stmt = ast.IfStmt{
        .condition = &condition,
        .then_block = then_stmts[0..],
        .else_block = null,
    };

    var body_stmts5 = [_]ast.Stmt{
        .{ .if_stmt = if_stmt },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = "TestError",
        .effects = &[_][]const u8{},
        .body = body_stmts5[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}
