const std = @import("std");
const exhaustiveness = @import("exhaustiveness.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");

test "match with wildcard should be considered exhaustive" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .identifier = .{ .name = "x", .loc = .{ .line = 1, .column = 1 } } };
    var body = ast.Expr{ .number = "42" };

    var arms1 = [_]ast.MatchArm{
        .{
            .pattern = .wildcard,
            .body = &body,
        },
    };
    const match_stmt = ast.MatchStmt{
        .value = &value,
        .arms = arms1[0..],
    };

    try checker.checkMatch(match_stmt);

    try std.testing.expect(!diag_list.hasErrors());
}

test "match without wildcard should warn" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .identifier = .{ .name = "x", .loc = .{ .line = 1, .column = 1 } } };
    var body = ast.Expr{ .number = "42" };

    var arms2 = [_]ast.MatchArm{
        .{
            .pattern = .{ .variant = .{ .name = "Some", .fields = null } },
            .body = &body,
        },
    };
    const match_stmt = ast.MatchStmt{
        .value = &value,
        .arms = arms2[0..],
    };

    try checker.checkMatch(match_stmt);

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "match with identifier pattern should be exhaustive" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .identifier = .{ .name = "x", .loc = .{ .line = 1, .column = 1 } } };
    var body = ast.Expr{ .number = "42" };

    var arms3 = [_]ast.MatchArm{
        .{
            .pattern = .{ .identifier = "value" },
            .body = &body,
        },
    };
    const match_stmt = ast.MatchStmt{
        .value = &value,
        .arms = arms3[0..],
    };

    try checker.checkMatch(match_stmt);

    try std.testing.expect(!diag_list.hasErrors());
}

test "match expression without wildcard should warn" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value = ast.Expr{ .identifier = .{ .name = "x", .loc = .{ .line = 1, .column = 1 } } };
    var body1 = ast.Expr{ .number = "1" };

    var arms4 = [_]ast.MatchArm{
        .{
            .pattern = .{ .number = "1" },
            .body = &body1,
        },
    };
    const match_expr = ast.MatchExpr{
        .value = &value,
        .arms = arms4[0..],
    };

    try checker.checkMatchExpr(match_expr);

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "check domain exhaustiveness with all variants covered" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 2);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };
    variants[1] = .{
        .name = "PermissionDenied",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var body1 = ast.Expr{ .number = "1" };
    var body2 = ast.Expr{ .number = "2" };

    var arms = [_]ast.MatchArm{
        .{
            .pattern = .{ .variant = .{ .name = "NotFound", .fields = null } },
            .body = &body1,
        },
        .{
            .pattern = .{ .variant = .{ .name = "PermissionDenied", .fields = null } },
            .body = &body2,
        },
    };

    const result = try checker.checkDomainExhaustiveness(arms[0..], "FileError");

    try std.testing.expect(result);
    try std.testing.expect(!diag_list.hasErrors());
}

test "check domain exhaustiveness with missing variant" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 2);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };
    variants[1] = .{
        .name = "PermissionDenied",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var body1 = ast.Expr{ .number = "1" };

    var arms = [_]ast.MatchArm{
        .{
            .pattern = .{ .variant = .{ .name = "NotFound", .fields = null } },
            .body = &body1,
        },
    };

    const result = try checker.checkDomainExhaustiveness(arms[0..], "FileError");

    try std.testing.expect(!result);
    try std.testing.expect(diag_list.hasErrors());
}

test "check domain exhaustiveness with wildcard" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const variants = try allocator.alloc(error_domains.ErrorVariant, 2);
    variants[0] = .{
        .name = "NotFound",
        .fields = &[_]error_domains.Field{},
    };
    variants[1] = .{
        .name = "PermissionDenied",
        .fields = &[_]error_domains.Field{},
    };

    const domain = error_domains.ErrorDomain{
        .name = "FileError",
        .variants = variants,
    };

    try domains.insert("FileError", domain);

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var body1 = ast.Expr{ .number = "1" };

    var arms = [_]ast.MatchArm{
        .{
            .pattern = .wildcard,
            .body = &body1,
        },
    };

    const result = try checker.checkDomainExhaustiveness(arms[0..], "FileError");

    try std.testing.expect(result);
    try std.testing.expect(!diag_list.hasErrors());
}

test "nested match statements should be checked" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = exhaustiveness.ExhaustivenessChecker.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var inner_value = ast.Expr{ .identifier = .{ .name = "y", .loc = .{ .line = 1, .column = 1 } } };
    var inner_body = ast.Expr{ .number = "1" };

    var inner_arms = [_]ast.MatchArm{
        .{
            .pattern = .{ .number = "1" },
            .body = &inner_body,
        },
    };
    var inner_match = ast.Expr{
        .match_expr = .{
            .value = &inner_value,
            .arms = inner_arms[0..],
        },
    };

    var func_body = [_]ast.Stmt{
        .{ .expr_stmt = &inner_match },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test",
        .type_params = null,
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = func_body[0..],
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try checker.checkStmt(.{ .function_decl = func_decl });

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}
