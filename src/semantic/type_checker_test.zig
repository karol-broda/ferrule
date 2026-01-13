const std = @import("std");
const type_checker = @import("type_checker.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const types = @import("../types.zig");
const hover_info = @import("../hover_info.zig");
const symbol_locations = @import("../symbol_locations.zig");
const context = @import("../context.zig");

test "check simple number literal" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var expr = ast.Expr{ .number = "42" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.i32, typed.resolved_type);
}

test "check float literal" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var expr = ast.Expr{ .number = "3.14" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.f64, typed.resolved_type);
}

test "check string literal" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var expr = ast.Expr{ .string = "hello" };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.string_type, typed.resolved_type);
}

test "check bool literal" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var expr = ast.Expr{ .bool_literal = true };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.bool_type, typed.resolved_type);
}

test "check undefined identifier should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var expr = ast.Expr{ .identifier = .{ .name = "undefined_var", .loc = .{ .line = 1, .column = 1, .length = 13 } } };
    const typed = try checker.checkExpr(&expr);

    // should return unit type for undefined identifier
    try std.testing.expectEqual(types.ResolvedType.unit_type, typed.resolved_type);
    // should have added an error
    try std.testing.expect(diag_list.hasErrors());
}

test "check variable declaration with matching types" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var value_expr = ast.Expr{ .number = "42" };
    const var_decl = ast.VarDecl{
        .name = "x",
        .name_loc = .{ .line = 1, .column = 5, .length = 1 },
        .type_annotation = .{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 8, .length = 3 } } },
        .value = &value_expr,
    };

    try checker.checkVarDecl(var_decl);

    // should not have any errors
    try std.testing.expect(!diag_list.hasErrors());
}

test "check binary addition of same types" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{ .binary = .{
        .left = &left,
        .right = &right,
        .op = .add,
    } };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.i32, typed.resolved_type);
    try std.testing.expect(!diag_list.hasErrors());
}

test "check binary comparison returns bool" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{ .binary = .{
        .left = &left,
        .right = &right,
        .op = .lt,
    } };
    const typed = try checker.checkExpr(&expr);

    try std.testing.expectEqual(types.ResolvedType.bool_type, typed.resolved_type);
    try std.testing.expect(!diag_list.hasErrors());
}

test "check logical operators require bool operands" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    // using numbers instead of bools should error
    var left = ast.Expr{ .number = "1" };
    var right = ast.Expr{ .number = "2" };
    var expr = ast.Expr{ .binary = .{
        .left = &left,
        .right = &right,
        .op = .logical_and,
    } };
    const typed = try checker.checkExpr(&expr);

    // should still return bool (the expected type)
    try std.testing.expectEqual(types.ResolvedType.bool_type, typed.resolved_type);
    // but should have an error
    try std.testing.expect(diag_list.hasErrors());
}

test "check if statement with non-bool condition should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
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

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var condition = ast.Expr{ .number = "42" };
    const while_stmt = ast.WhileStmt{
        .condition = &condition,
        .body = &[_]ast.Stmt{},
    };

    try checker.checkWhileStmt(while_stmt);

    try std.testing.expect(diag_list.hasErrors());
}

test "check function call with wrong argument count should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    // add a function to the symbol table
    const params = try ctx.permanentAllocator().alloc(types.ResolvedType, 1);
    params[0] = types.ResolvedType.i32;
    const param_names = try ctx.permanentAllocator().alloc([]const u8, 1);
    param_names[0] = "x";
    const is_cap = try ctx.permanentAllocator().alloc(bool, 1);
    is_cap[0] = false;

    try symbols.insertGlobal("test_func", .{
        .function = .{
            .name = "test_func",
            .type_params = null,
            .params = params,
            .param_names = param_names,
            .return_type = types.ResolvedType.i32,
            .effects = &[_]types.Effect{},
            .error_domain = null,
            .is_capability_param = is_cap,
        },
    });

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    // call with no arguments (should require 1)
    var callee = ast.Expr{ .identifier = .{ .name = "test_func", .loc = .{ .line = 1, .column = 1, .length = 9 } } };
    var expr = ast.Expr{ .call = .{
        .callee = &callee,
        .args = &[_]*ast.Expr{},
    } };

    _ = try checker.checkExpr(&expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "check assignment to immutable variable should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    // add an immutable variable to the symbol table
    try symbols.insertGlobal("x", .{
        .constant = .{
            .name = "x",
            .type_annotation = types.ResolvedType.i32,
            .scope_level = 0,
        },
    });

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var value = ast.Expr{ .number = "42" };
    const assign = ast.AssignStmt{
        .target = .{ .name = "x", .loc = .{ .line = 1, .column = 1, .length = 1 } },
        .value = &value,
    };

    try checker.checkAssignStmt(assign);

    try std.testing.expect(diag_list.hasErrors());
}

test "check return type mismatch should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    // add a function that returns i32
    const params = try ctx.permanentAllocator().alloc(types.ResolvedType, 0);
    const param_names = try ctx.permanentAllocator().alloc([]const u8, 0);
    const is_cap = try ctx.permanentAllocator().alloc(bool, 0);

    try symbols.insertGlobal("test_func", .{
        .function = .{
            .name = "test_func",
            .type_params = null,
            .params = params,
            .param_names = param_names,
            .return_type = types.ResolvedType.i32,
            .effects = &[_]types.Effect{},
            .error_domain = null,
            .is_capability_param = is_cap,
        },
    });

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    // set current function context
    if (symbols.lookupGlobal("test_func")) |sym| {
        if (sym == .function) {
            var func_sym = sym.function;
            checker.current_function = &func_sym;
        }
    }

    // return a string instead of i32
    var value = ast.Expr{ .string = "hello" };
    const return_stmt = ast.ReturnStmt{
        .value = &value,
        .loc = .{ .line = 1, .column = 1, .length = 6 },
    };

    try checker.checkReturnStmt(return_stmt);

    try std.testing.expect(diag_list.hasErrors());
}

test "check ensure with non-bool condition should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    // ensure without being in an error domain should error
    var condition = ast.Expr{ .number = "42" };
    var expr = ast.Expr{ .ensure = .{
        .condition = &condition,
        .error_expr = .{
            .variant = "SomeError",
            .fields = &[_]ast.FieldAssignment{},
        },
    } };

    _ = try checker.checkExpr(&expr);

    // should error because we're not in a function with an error domain
    try std.testing.expect(diag_list.hasErrors());
}

test "check match arms with different types should error" {
    const allocator = std.testing.allocator;

    var ctx = context.CompilationContext.init(allocator);
    defer ctx.deinit();

    var symbols = symbol_table.SymbolTable.init(&ctx);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(ctx.permanentAllocator());

    var hover_table = hover_info.HoverInfoTable.init(&ctx);
    defer hover_table.deinit();

    var location_table = symbol_locations.SymbolLocationTable.init(&ctx);
    defer location_table.deinit();

    var checker = type_checker.TypeChecker.init(
        &ctx,
        &symbols,
        &diag_list,
        "test.fe",
        &hover_table,
        &location_table,
    );

    var match_value = ast.Expr{ .number = "42" };
    var arm1_body = ast.Expr{ .number = "1" };
    var arm2_body = ast.Expr{ .string = "hello" };

    var arms = [_]ast.MatchArm{
        .{ .pattern = .{ .number = "1" }, .body = &arm1_body },
        .{ .pattern = .wildcard, .body = &arm2_body },
    };

    var expr = ast.Expr{ .match_expr = .{
        .value = &match_value,
        .arms = arms[0..],
    } };
    _ = try checker.checkExpr(&expr);

    // should error because arms have different types
    try std.testing.expect(diag_list.hasErrors());
}
