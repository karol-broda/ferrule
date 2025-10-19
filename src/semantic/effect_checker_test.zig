const std = @import("std");
const effect_checker = @import("effect_checker.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const types = @import("../types.zig");

test "function with declared effect should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const effects = try allocator.alloc(types.Effect, 1);
    defer allocator.free(effects);
    effects[0] = .io;

    const params_types = try allocator.alloc(types.ResolvedType, 1);
    defer allocator.free(params_types);
    params_types[0] = .unit_type;

    var is_cap_params = [_]bool{true};
    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .params = params_types,
            .return_type = .unit_type,
            .effects = effects,
            .error_domain = null,
            .is_capability_param = is_cap_params[0..],
        },
    };

    try symbols.insertGlobal("test_func", func_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var io_effect = [_][]const u8{"io"};
    const io_param = ast.Param{
        .name = "io_cap",
        .type_annotation = .{ .simple = "Io" },
        .is_capability = true,
        .is_inout = false,
    };
    var params = [_]ast.Param{io_param};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = params[0..],
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = io_effect[0..],
        .body = &[_]ast.Stmt{},
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "function using undeclared effect should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const callee_effects = try allocator.alloc(types.Effect, 1);
    defer allocator.free(callee_effects);
    callee_effects[0] = .io;

    const callee_symbol = symbol_table.Symbol{
        .function = .{
            .name = "io_func",
            .params = &[_]types.ResolvedType{},
            .return_type = .unit_type,
            .effects = callee_effects,
            .error_domain = null,
            .is_capability_param = &[_]bool{},
        },
    };

    try symbols.insertGlobal("io_func", callee_symbol);

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "caller",
            .params = &[_]types.ResolvedType{},
            .return_type = .unit_type,
            .effects = &[_]types.Effect{},
            .error_domain = null,
            .is_capability_param = &[_]bool{},
        },
    };

    try symbols.insertGlobal("caller", func_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var callee_expr = ast.Expr{ .identifier = "io_func" };
    var call_expr = ast.Expr{
        .call = .{
            .callee = &callee_expr,
            .args = &[_]*ast.Expr{},
        },
    };

    var body_stmts = [_]ast.Stmt{
        .{ .expr_stmt = &call_expr },
    };
    const func_decl = ast.FunctionDecl{
        .name = "caller",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body_stmts[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "effect requiring capability without capability parameter should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const effects = try allocator.alloc(types.Effect, 1);
    defer allocator.free(effects);
    effects[0] = .fs;

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .params = &[_]types.ResolvedType{},
            .return_type = .unit_type,
            .effects = effects,
            .error_domain = null,
            .is_capability_param = &[_]bool{},
        },
    };

    try symbols.insertGlobal("test_func", func_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var fs_effect = [_][]const u8{"fs"};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = fs_effect[0..],
        .body = &[_]ast.Stmt{},
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "effect with correct capability parameter should not error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const effects = try allocator.alloc(types.Effect, 1);
    defer allocator.free(effects);
    effects[0] = .fs;

    const param_types = try allocator.alloc(types.ResolvedType, 1);
    defer allocator.free(param_types);
    param_types[0] = .unit_type;

    const is_cap = try allocator.alloc(bool, 1);
    defer allocator.free(is_cap);
    is_cap[0] = true;

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .params = param_types,
            .return_type = .unit_type,
            .effects = effects,
            .error_domain = null,
            .is_capability_param = is_cap,
        },
    };

    try symbols.insertGlobal("test_func", func_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var params = [_]ast.Param{
        .{
            .name = "fs_cap",
            .type_annotation = .{ .simple = "Fs" },
            .is_inout = false,
            .is_capability = true,
        },
    };
    var fs_effect2 = [_][]const u8{"fs"};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = params[0..],
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = fs_effect2[0..],
        .body = &[_]ast.Stmt{},
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(!diag_list.hasErrors());
}

test "isCapabilityForEffect correctly identifies capabilities" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = "Fs" }, .fs));
    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = "Net" }, .net));
    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = "Io" }, .io));
    try std.testing.expect(!checker.isCapabilityForEffect(.{ .simple = "Fs" }, .net));
    try std.testing.expect(!checker.isCapabilityForEffect(.{ .simple = "Wrong" }, .fs));
}

test "requiresCapability returns correct values" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    try std.testing.expect(checker.requiresCapability(.fs));
    try std.testing.expect(checker.requiresCapability(.net));
    try std.testing.expect(checker.requiresCapability(.io));
    try std.testing.expect(!checker.requiresCapability(.alloc));
    try std.testing.expect(!checker.requiresCapability(.cpu));
}

test "nested function calls propagate effects" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const inner_effects = try allocator.alloc(types.Effect, 1);
    defer allocator.free(inner_effects);
    inner_effects[0] = .io;

    const inner_symbol = symbol_table.Symbol{
        .function = .{
            .name = "inner",
            .params = &[_]types.ResolvedType{},
            .return_type = .unit_type,
            .effects = inner_effects,
            .error_domain = null,
            .is_capability_param = &[_]bool{},
        },
    };

    try symbols.insertGlobal("inner", inner_symbol);

    const outer_symbol = symbol_table.Symbol{
        .function = .{
            .name = "outer",
            .params = &[_]types.ResolvedType{},
            .return_type = .unit_type,
            .effects = &[_]types.Effect{},
            .error_domain = null,
            .is_capability_param = &[_]bool{},
        },
    };

    try symbols.insertGlobal("outer", outer_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var inner_callee = ast.Expr{ .identifier = "inner" };
    var inner_call = ast.Expr{
        .call = .{
            .callee = &inner_callee,
            .args = &[_]*ast.Expr{},
        },
    };

    var body_stmts2 = [_]ast.Stmt{
        .{ .expr_stmt = &inner_call },
    };
    const func_decl = ast.FunctionDecl{
        .name = "outer",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = "()" },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body_stmts2[0..],
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}
