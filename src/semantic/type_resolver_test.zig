const std = @import("std");
const type_resolver = @import("type_resolver.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const types = @import("../types.zig");

test "resolve primitive types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const resolved_i32 = try resolver.resolve(.{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } });
    try std.testing.expectEqual(types.ResolvedType.i32, resolved_i32);

    const resolved_i64 = try resolver.resolve(.{ .simple = .{ .name = "i64", .loc = .{ .line = 1, .column = 1 } } });
    try std.testing.expectEqual(types.ResolvedType.i64, resolved_i64);

    const resolved_f32 = try resolver.resolve(.{ .simple = .{ .name = "f32", .loc = .{ .line = 1, .column = 1 } } });
    try std.testing.expectEqual(types.ResolvedType.f32, resolved_f32);

    const resolved_bool = try resolver.resolve(.{ .simple = .{ .name = "Bool", .loc = .{ .line = 1, .column = 1 } } });
    try std.testing.expectEqual(types.ResolvedType.bool_type, resolved_bool);

    const resolved_string = try resolver.resolve(.{ .simple = .{ .name = "String", .loc = .{ .line = 1, .column = 1 } } });
    try std.testing.expectEqual(types.ResolvedType.string_type, resolved_string);
}

test "resolve unknown type should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    _ = try resolver.resolve(.{ .simple = .{ .name = "UnknownType", .loc = .{ .line = 1, .column = 1 } } });

    try std.testing.expect(diag_list.hasErrors());
}

test "resolve named type from symbol table" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    const type_symbol = symbol_table.Symbol{
        .type_def = .{
            .name = "MyInt",
            .type_params = null,
            .underlying = .i32,
        },
    };

    try symbols.insertGlobal("MyInt", type_symbol);

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const resolved = try resolver.resolve(.{ .simple = .{ .name = "MyInt", .loc = .{ .line = 1, .column = 1 } } });
    // manually free underlying pointer only - name is a static string from the symbol table
    defer allocator.destroy(resolved.named.underlying);

    try std.testing.expect(resolved == .named);
    try std.testing.expectEqualStrings("MyInt", resolved.named.name);
}

test "resolve array type" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var element_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };
    var size_expr = ast.Expr{ .number = "10" };

    const array_type = ast.Type{
        .array = .{
            .element_type = &element_type,
            .size = &size_expr,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(array_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .array);
    try std.testing.expectEqual(@as(usize, 10), resolved.array.size);
    try std.testing.expectEqual(types.ResolvedType.i32, resolved.array.element_type.*);
}

test "resolve vector type" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var element_type = ast.Type{ .simple = .{ .name = "f32", .loc = .{ .line = 1, .column = 1 } } };
    var size_expr = ast.Expr{ .number = "4" };

    const vector_type = ast.Type{
        .vector = .{
            .element_type = &element_type,
            .size = &size_expr,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(vector_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .vector);
    try std.testing.expectEqual(@as(usize, 4), resolved.vector.size);
    try std.testing.expectEqual(types.ResolvedType.f32, resolved.vector.element_type.*);
}

test "resolve view type immutable" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var element_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };

    const view_type = ast.Type{
        .view = .{
            .element_type = &element_type,
            .mutable = false,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(view_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .view);
    try std.testing.expect(!resolved.view.mutable);
    try std.testing.expectEqual(types.ResolvedType.i32, resolved.view.element_type.*);
}

test "resolve view type mutable" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var element_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };

    const view_type = ast.Type{
        .view = .{
            .element_type = &element_type,
            .mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(view_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .view);
    try std.testing.expect(resolved.view.mutable);
}

test "resolve nullable type" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var inner_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };

    const nullable_type = ast.Type{ .nullable = .{ .inner = &inner_type, .loc = .{ .line = 1, .column = 1 } } };

    const resolved = try resolver.resolve(nullable_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .nullable);
    try std.testing.expectEqual(types.ResolvedType.i32, resolved.nullable.*);
}

test "resolve function type with no effects" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const param_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };
    var return_type = ast.Type{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } };

    var func_params = [_]ast.Type{param_type};
    const func_type = ast.Type{
        .function_type = .{
            .params = func_params[0..],
            .return_type = &return_type,
            .error_domain = null,
            .effects = &[_][]const u8{},
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(func_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .function_type);
    try std.testing.expectEqual(@as(usize, 1), resolved.function_type.params.len);
    try std.testing.expectEqual(types.ResolvedType.i32, resolved.function_type.params[0]);
    try std.testing.expectEqual(types.ResolvedType.i32, resolved.function_type.return_type.*);
}

test "resolve function type with effects" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var return_type = ast.Type{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } };

    var func_effects = [_][]const u8{ "io", "fs" };
    const func_type = ast.Type{
        .function_type = .{
            .params = &[_]ast.Type{},
            .return_type = &return_type,
            .error_domain = null,
            .effects = func_effects[0..],
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const resolved = try resolver.resolve(func_type);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved == .function_type);
    try std.testing.expectEqual(@as(usize, 2), resolved.function_type.effects.len);
    try std.testing.expectEqual(types.Effect.io, resolved.function_type.effects[0]);
    try std.testing.expectEqual(types.Effect.fs, resolved.function_type.effects[1]);
}

test "resolve function type with unknown effect should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var return_type = ast.Type{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } };

    var unknown_effects = [_][]const u8{"unknown_effect"};
    const func_type = ast.Type{
        .function_type = .{
            .params = &[_]ast.Type{},
            .return_type = &return_type,
            .error_domain = null,
            .effects = unknown_effects[0..],
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    _ = try resolver.resolve(func_type);

    try std.testing.expect(diag_list.hasErrors());
}

test "evaluate const expression for array size" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var size_expr = ast.Expr{ .number = "42" };
    const size = try resolver.evaluateConstExpr(&size_expr);

    try std.testing.expectEqual(@as(usize, 42), size);
}

test "evaluate invalid const expression should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var size_expr = ast.Expr{ .identifier = .{ .name = "not_const", .loc = .{ .line = 1, .column = 1 } } };
    _ = try resolver.evaluateConstExpr(&size_expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "evaluate non-numeric const expression should error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    var size_expr = ast.Expr{ .number = "not_a_number" };
    _ = try resolver.evaluateConstExpr(&size_expr);

    try std.testing.expect(diag_list.hasErrors());
}

test "resolve all primitive integer types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const int_types = [_]struct { name: []const u8, expected: types.ResolvedType }{
        .{ .name = "i8", .expected = .i8 },
        .{ .name = "i16", .expected = .i16 },
        .{ .name = "i32", .expected = .i32 },
        .{ .name = "i64", .expected = .i64 },
        .{ .name = "i128", .expected = .i128 },
        .{ .name = "u8", .expected = .u8 },
        .{ .name = "u16", .expected = .u16 },
        .{ .name = "u32", .expected = .u32 },
        .{ .name = "u64", .expected = .u64 },
        .{ .name = "u128", .expected = .u128 },
        .{ .name = "usize", .expected = .usize_type },
    };

    for (int_types) |int_type| {
        const resolved = try resolver.resolve(.{ .simple = .{ .name = int_type.name, .loc = .{ .line = 1, .column = 1 } } });
        try std.testing.expectEqual(int_type.expected, resolved);
    }
}

test "resolve all primitive float types" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    const float_types = [_]struct { name: []const u8, expected: types.ResolvedType }{
        .{ .name = "f16", .expected = .f16 },
        .{ .name = "f32", .expected = .f32 },
        .{ .name = "f64", .expected = .f64 },
    };

    for (float_types) |float_type| {
        const resolved = try resolver.resolve(.{ .simple = .{ .name = float_type.name, .loc = .{ .line = 1, .column = 1 } } });
        try std.testing.expectEqual(float_type.expected, resolved);
    }
}

test "non-type symbol should error when resolved as type" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    // heap allocate arrays that will be freed by symbol table deinit
    const func_params = try allocator.alloc(types.ResolvedType, 0);
    const func_param_names = try allocator.alloc([]const u8, 0);
    const func_effects = try allocator.alloc(types.Effect, 0);
    const func_is_cap = try allocator.alloc(bool, 0);

    const func_symbol = symbol_table.Symbol{
        .function = .{
            .name = "not_a_type",
            .type_params = null,
            .params = func_params,
            .param_names = func_param_names,
            .return_type = .unit_type,
            .effects = func_effects,
            .error_domain = null,
            .is_capability_param = func_is_cap,
        },
    };

    try symbols.insertGlobal("not_a_type", func_symbol);

    var resolver = type_resolver.TypeResolver.init(
        allocator,
        &symbols,
        &diag_list,
        "test.fe",
    );

    _ = try resolver.resolve(.{ .simple = .{ .name = "not_a_type", .loc = .{ .line = 1, .column = 1 } } });

    try std.testing.expect(diag_list.hasErrors());
}
