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

    // heap allocate arrays that will be freed by symbol table deinit
    const effects = try allocator.alloc(types.Effect, 1);
    effects[0] = .io;

    const params_types = try allocator.alloc(types.ResolvedType, 1);
    params_types[0] = .unit_type;

    const param_names = try allocator.alloc([]const u8, 1);
    param_names[0] = "cap";

    const is_cap_params = try allocator.alloc(bool, 1);
    is_cap_params[0] = true;

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .type_params = null,
            .params = params_types,
            .param_names = param_names,
            .return_type = .unit_type,
            .effects = effects,
            .error_domain = null,
            .is_capability_param = is_cap_params,
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
        .type_annotation = .{ .simple = .{ .name = "Io", .loc = .{ .line = 1, .column = 1 } } },
        .is_capability = true,
        .is_inout = false,
        .name_loc = .{ .line = 1, .column = 1 },
    };
    var params = [_]ast.Param{io_param};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .type_params = null,
        .params = params[0..],
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = io_effect[0..],
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
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

    // heap allocate arrays for callee symbol
    const callee_effects = try allocator.alloc(types.Effect, 1);
    callee_effects[0] = .io;
    const callee_params = try allocator.alloc(types.ResolvedType, 0);
    const callee_param_names = try allocator.alloc([]const u8, 0);
    const callee_is_cap = try allocator.alloc(bool, 0);

    const callee_symbol = symbol_table.Symbol{
        .function = .{
            .name = "io_func",
            .type_params = null,
            .params = callee_params,
            .param_names = callee_param_names,
            .return_type = .unit_type,
            .effects = callee_effects,
            .error_domain = null,
            .is_capability_param = callee_is_cap,
        },
    };

    try symbols.insertGlobal("io_func", callee_symbol);

    // heap allocate arrays for caller symbol
    const caller_params = try allocator.alloc(types.ResolvedType, 0);
    const caller_param_names = try allocator.alloc([]const u8, 0);
    const caller_effects = try allocator.alloc(types.Effect, 0);
    const caller_is_cap = try allocator.alloc(bool, 0);

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "caller",
            .type_params = null,
            .params = caller_params,
            .param_names = caller_param_names,
            .return_type = .unit_type,
            .effects = caller_effects,
            .error_domain = null,
            .is_capability_param = caller_is_cap,
        },
    };

    try symbols.insertGlobal("caller", func_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var callee_expr = ast.Expr{ .identifier = .{ .name = "io_func", .loc = .{ .line = 1, .column = 1 } } };
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
        .type_params = null,
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body_stmts[0..],
        .name_loc = .{ .line = 1, .column = 1 },
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

    // heap allocate arrays
    const effects = try allocator.alloc(types.Effect, 1);
    effects[0] = .fs;
    const params = try allocator.alloc(types.ResolvedType, 0);
    const param_names = try allocator.alloc([]const u8, 0);
    const is_cap = try allocator.alloc(bool, 0);

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .type_params = null,
            .params = params,
            .param_names = param_names,
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

    var fs_effect = [_][]const u8{"fs"};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .type_params = null,
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = fs_effect[0..],
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
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

    // heap allocate arrays
    const effects = try allocator.alloc(types.Effect, 1);
    effects[0] = .fs;

    const param_types = try allocator.alloc(types.ResolvedType, 1);
    param_types[0] = .unit_type;

    const is_cap = try allocator.alloc(bool, 1);
    is_cap[0] = true;

    const param_names = try allocator.alloc([]const u8, 1);
    param_names[0] = "fs_cap";

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "test_func",
            .type_params = null,
            .params = param_types,
            .param_names = param_names,
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
            .type_annotation = .{ .simple = .{ .name = "Fs", .loc = .{ .line = 1, .column = 1 } } },
            .is_inout = false,
            .is_capability = true,
            .name_loc = .{ .line = 1, .column = 1 },
        },
    };
    var fs_effect2 = [_][]const u8{"fs"};
    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .type_params = null,
        .params = params[0..],
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = fs_effect2[0..],
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
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

    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = .{ .name = "Fs", .loc = .{ .line = 1, .column = 1 } } }, .fs));
    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = .{ .name = "Net", .loc = .{ .line = 1, .column = 1 } } }, .net));
    try std.testing.expect(checker.isCapabilityForEffect(.{ .simple = .{ .name = "Io", .loc = .{ .line = 1, .column = 1 } } }, .io));
    try std.testing.expect(!checker.isCapabilityForEffect(.{ .simple = .{ .name = "Fs", .loc = .{ .line = 1, .column = 1 } } }, .net));
    try std.testing.expect(!checker.isCapabilityForEffect(.{ .simple = .{ .name = "Wrong", .loc = .{ .line = 1, .column = 1 } } }, .fs));
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

    // heap allocate arrays for inner symbol
    const inner_effects = try allocator.alloc(types.Effect, 1);
    inner_effects[0] = .io;
    const inner_params = try allocator.alloc(types.ResolvedType, 0);
    const inner_param_names = try allocator.alloc([]const u8, 0);
    const inner_is_cap = try allocator.alloc(bool, 0);

    const inner_symbol = symbol_table.Symbol{
        .function = .{
            .name = "inner",
            .type_params = null,
            .params = inner_params,
            .param_names = inner_param_names,
            .return_type = .unit_type,
            .effects = inner_effects,
            .error_domain = null,
            .is_capability_param = inner_is_cap,
        },
    };

    try symbols.insertGlobal("inner", inner_symbol);

    // heap allocate arrays for outer symbol
    const outer_params = try allocator.alloc(types.ResolvedType, 0);
    const outer_param_names = try allocator.alloc([]const u8, 0);
    const outer_effects = try allocator.alloc(types.Effect, 0);
    const outer_is_cap = try allocator.alloc(bool, 0);

    const outer_symbol = symbol_table.Symbol{
        .function = .{
            .name = "outer",
            .type_params = null,
            .params = outer_params,
            .param_names = outer_param_names,
            .return_type = .unit_type,
            .effects = outer_effects,
            .error_domain = null,
            .is_capability_param = outer_is_cap,
        },
    };

    try symbols.insertGlobal("outer", outer_symbol);

    var checker = effect_checker.EffectChecker.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var inner_callee = ast.Expr{ .identifier = .{ .name = "inner", .loc = .{ .line = 1, .column = 1 } } };
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
        .type_params = null,
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = body_stmts2[0..],
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try checker.checkFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}
