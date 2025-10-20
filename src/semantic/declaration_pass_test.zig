const std = @import("std");
const declaration_pass = @import("declaration_pass.zig");
const ast = @import("../ast.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");
const types = @import("../types.zig");

test "collect simple function declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const func_decl = ast.FunctionDecl{
        .name = "test_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectFunction(func_decl);

    const symbol = symbols.lookupGlobal("test_func");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .function);
    try std.testing.expectEqualStrings("test_func", symbol.?.function.name);
}

test "detect duplicate function declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const func_decl = ast.FunctionDecl{
        .name = "duplicate",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = &[_][]const u8{},
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectFunction(func_decl);
    try collector.collectFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "collect function with effects" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var io_effect = [_][]const u8{"io"};
    const func_decl = ast.FunctionDecl{
        .name = "io_func",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = io_effect[0..],
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectFunction(func_decl);

    const symbol = symbols.lookupGlobal("io_func");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .function);
    try std.testing.expectEqual(@as(usize, 1), symbol.?.function.effects.len);

    try std.testing.expectEqual(types.Effect.io, symbol.?.function.effects[0]);
}

test "collect unknown effect results in error" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var unknown_effect = [_][]const u8{"unknown_effect"};
    const func_decl = ast.FunctionDecl{
        .name = "bad_effect",
        .params = &[_]ast.Param{},
        .return_type = .{ .simple = .{ .name = "()", .loc = .{ .line = 1, .column = 1 } } },
        .error_domain = null,
        .effects = unknown_effect[0..],
        .body = &[_]ast.Stmt{},
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectFunction(func_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "collect type declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const type_decl = ast.TypeDecl{
        .name = "MyType",
        .type_expr = .{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } },
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectTypeDecl(type_decl);

    const symbol = symbols.lookupGlobal("MyType");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .type_def);
    try std.testing.expectEqualStrings("MyType", symbol.?.type_def.name);
}

test "detect duplicate type declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const type_decl = ast.TypeDecl{
        .name = "DupType",
        .type_expr = .{ .simple = .{ .name = "i32", .loc = .{ .line = 1, .column = 1 } } },
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectTypeDecl(type_decl);
    try collector.collectTypeDecl(type_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "collect domain declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var variants = [_]ast.DomainVariant{
        .{ .name = "NotFound", .fields = &[_]ast.Field{} },
        .{ .name = "PermissionDenied", .fields = &[_]ast.Field{} },
    };
    const domain_decl = ast.DomainDecl{
        .name = "FileError",
        .variants = variants[0..],
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectDomain(domain_decl);

    const symbol = symbols.lookupGlobal("FileError");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .domain);

    const domain = domains.get("FileError");
    try std.testing.expect(domain != null);
    try std.testing.expectEqual(@as(usize, 2), domain.?.variants.len);
}

test "detect duplicate domain declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const domain_decl = ast.DomainDecl{
        .name = "DupDomain",
        .variants = &[_]ast.DomainVariant{},
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectDomain(domain_decl);
    try collector.collectDomain(domain_decl);

    try std.testing.expect(diag_list.hasErrors());
}

test "collect role declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    const role_decl = ast.RoleDecl{
        .name = "Admin",
    };

    try collector.collectRole(role_decl);

    const symbol = symbols.lookupGlobal("Admin");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .role);
}

test "collect const declaration" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value_expr = ast.Expr{ .number = "42" };
    const const_decl = ast.ConstDecl{
        .name = "MY_CONST",
        .type_annotation = null,
        .value = &value_expr,
        .name_loc = .{ .line = 1, .column = 1 },
    };

    try collector.collectConst(const_decl);

    const symbol = symbols.lookupGlobal("MY_CONST");
    try std.testing.expect(symbol != null);
    try std.testing.expect(symbol.? == .constant);
}

test "collect module with multiple declarations" {
    const allocator = std.testing.allocator;

    var symbols = symbol_table.SymbolTable.init(allocator);
    defer symbols.deinit();

    var domains = error_domains.ErrorDomainTable.init(allocator);
    defer domains.deinit();

    var diag_list = diagnostics.DiagnosticList.init(allocator);
    defer diag_list.deinit();

    var collector = declaration_pass.DeclarationCollector.init(
        allocator,
        &symbols,
        &domains,
        &diag_list,
        "test.fe",
    );

    var value_expr = ast.Expr{ .number = "42" };

    var statements = [_]ast.Stmt{
        .{ .function_decl = .{
            .name = "func1",
            .params = &[_]ast.Param{},
            .return_type = .{ .simple = "()" },
            .error_domain = null,
            .effects = &[_][]const u8{},
            .body = &[_]ast.Stmt{},
        } },
        .{ .type_decl = .{
            .name = "Type1",
            .type_expr = .{ .simple = "i32" },
        } },
        .{ .const_decl = .{
            .name = "CONST1",
            .type_annotation = null,
            .value = &value_expr,
        } },
    };

    const module = ast.Module{
        .package_decl = null,
        .imports = &[_]ast.ImportDecl{},
        .statements = statements[0..],
    };

    try collector.collect(module);

    try std.testing.expect(symbols.lookupGlobal("func1") != null);
    try std.testing.expect(symbols.lookupGlobal("Type1") != null);
    try std.testing.expect(symbols.lookupGlobal("CONST1") != null);
}
