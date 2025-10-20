const std = @import("std");
const region_checker = @import("region_checker.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");

test "region variable should be tracked" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var value = ast.Expr{ .identifier = "create_region" };

    const var_decl = ast.VarDecl{
        .name = "r",
        .type_annotation = .{ .simple = .{ .name = "Region", .loc = .{ .line = 1, .column = 1 } } },
        .value = &value,
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try checker.checkStmt(.{ .var_decl = var_decl });

    try std.testing.expectEqual(@as(usize, 1), checker.active_regions.items.len);
    try std.testing.expectEqualStrings("r", checker.active_regions.items[0].name);
}

test "region without disposal should warn" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var value = ast.Expr{ .identifier = "create_region" };

    var body1 = [_]ast.Stmt{
        .{ .var_decl = .{
            .name = "r",
            .type_annotation = .{ .simple = "Region" },
            .value = &value,
        } },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body1[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "region with defer dispose should not warn" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var value = ast.Expr{ .identifier = "create_region" };
    var region_id = ast.Expr{ .identifier = "r" };
    var field_access = ast.Expr{
        .field_access = .{
            .object = &region_id,
            .field = "dispose",
        },
    };
    var dispose_call = ast.Expr{
        .call = .{
            .callee = &field_access,
            .args = &[_]*ast.Expr{},
        },
    };

    var body2 = [_]ast.Stmt{
        .{ .var_decl = .{
            .name = "r",
            .type_annotation = .{ .simple = "Region" },
            .value = &value,
        } },
        .{ .defer_stmt = &dispose_call },
    };
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body2[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(checker.active_regions.items[0].is_disposed);
}

test "region escaping scope should warn" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var value = ast.Expr{ .identifier = "create_region" };
    var condition = ast.Expr{ .bool_literal = true };

    var then_stmts = [_]ast.Stmt{
        .{ .var_decl = .{
            .name = "r",
            .type_annotation = .{ .simple = "Region" },
            .value = &value,
        } },
    };
    const if_stmt = ast.IfStmt{
        .condition = &condition,
        .then_block = then_stmts[0..],
        .else_block = null,
    };

    try checker.checkStmt(.{ .if_stmt = if_stmt });

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "scope level should increase in nested blocks" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    try std.testing.expectEqual(@as(u32, 0), checker.current_scope_level);

    var condition = ast.Expr{ .bool_literal = true };

    const if_stmt = ast.IfStmt{
        .condition = &condition,
        .then_block = &[_]ast.Stmt{},
        .else_block = null,
    };

    try checker.checkStmt(.{ .if_stmt = if_stmt });

    try std.testing.expectEqual(@as(u32, 0), checker.current_scope_level);
}

test "while loop should check region disposal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var condition = ast.Expr{ .bool_literal = true };
    var value = ast.Expr{ .identifier = "create_region" };

    var body3 = [_]ast.Stmt{
        .{ .var_decl = .{
            .name = "r",
            .type_annotation = .{ .simple = "Region" },
            .value = &value,
        } },
    };
    const while_stmt = ast.WhileStmt{
        .condition = &condition,
        .body = body3[0..],
    };

    try checker.checkStmt(.{ .while_stmt = while_stmt });

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "for loop should check region disposal" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var iterable = ast.Expr{ .identifier = "items" };
    var value = ast.Expr{ .identifier = "create_region" };

    var body4 = [_]ast.Stmt{
        .{ .var_decl = .{
            .name = "r",
            .type_annotation = .{ .simple = "Region" },
            .value = &value,
        } },
    };
    const for_stmt = ast.ForStmt{
        .iterator = "item",
        .iterator_loc = .{ .line = 1, .column = 1 },
        .iterable = &iterable,
        .body = body4[0..],
    };

    try checker.checkStmt(.{ .for_stmt = for_stmt });

    try std.testing.expect(diag_list.diagnostics.items.len > 0);
}

test "isRegionType correctly identifies region types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    try std.testing.expect(checker.isRegionType(.{ .simple = "Region" }));
    try std.testing.expect(!checker.isRegionType(.{ .simple = "i32" }));
    try std.testing.expect(!checker.isRegionType(.{ .simple = "String" }));
}

test "non-region variables should not be tracked" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = region_checker.RegionChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );
    defer checker.deinit();

    var value = ast.Expr{ .number = "42" };

    const var_decl = ast.VarDecl{
        .name = "x",
        .type_annotation = .{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } },
        .value = &value,
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try checker.checkStmt(.{ .var_decl = var_decl });

    try std.testing.expectEqual(@as(usize, 0), checker.active_regions.items.len);
}
