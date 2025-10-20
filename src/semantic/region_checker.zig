const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");

pub const RegionInfo = struct {
    name: []const u8,
    scope_level: u32,
    is_disposed: bool,
};

pub const RegionChecker = struct {
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    active_regions: std.ArrayList(RegionInfo),
    current_scope_level: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        symbols: *symbol_table.SymbolTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) RegionChecker {
        return .{
            .symbols = symbols,
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
            .active_regions = std.ArrayList(RegionInfo){},
            .current_scope_level = 0,
        };
    }

    pub fn deinit(self: *RegionChecker) void {
        self.active_regions.deinit(self.allocator);
    }

    pub fn checkModule(self: *RegionChecker, module: ast.Module) !void {
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.checkFunction(stmt.function_decl);
            }
        }
    }

    pub fn checkFunction(self: *RegionChecker, func: ast.FunctionDecl) !void {
        self.current_scope_level = 0;
        self.active_regions.clearRetainingCapacity();

        for (func.body) |stmt| {
            try self.checkStmt(stmt);
        }

        for (self.active_regions.items) |region| {
            if (!region.is_disposed) {
                try self.diagnostics_list.addWarning(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "region '{s}' may not be properly disposed",
                        .{region.name},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = region.name.len,
                    },
                    try self.allocator.dupe(u8, "ensure region is disposed with 'defer region.dispose()' or explicitly returned"),
                );
            }
        }
    }

    pub fn checkStmt(self: *RegionChecker, stmt: ast.Stmt) !void {
        switch (stmt) {
            .expr_stmt => |expr| try self.checkExpr(expr),
            .var_decl => |vd| {
                try self.checkExpr(vd.value);
                if (vd.type_annotation) |type_annotation| {
                    if (self.isRegionType(type_annotation)) {
                        try self.active_regions.append(self.allocator, .{
                            .name = vd.name,
                            .scope_level = self.current_scope_level,
                            .is_disposed = false,
                        });
                    }
                }
            },
            .if_stmt => |is| {
                try self.checkExpr(is.condition);
                self.current_scope_level += 1;
                for (is.then_block) |then_stmt| {
                    try self.checkStmt(then_stmt);
                }
                if (is.else_block) |else_block| {
                    for (else_block) |else_stmt| {
                        try self.checkStmt(else_stmt);
                    }
                }
                try self.checkRegionsAtScopeExit();
                self.current_scope_level -= 1;
            },
            .while_stmt => |ws| {
                try self.checkExpr(ws.condition);
                self.current_scope_level += 1;
                for (ws.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
                try self.checkRegionsAtScopeExit();
                self.current_scope_level -= 1;
            },
            .for_stmt => |fs| {
                try self.checkExpr(fs.iterable);
                self.current_scope_level += 1;
                for (fs.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
                try self.checkRegionsAtScopeExit();
                self.current_scope_level -= 1;
            },
            .match_stmt => |ms| {
                try self.checkExpr(ms.value);
                for (ms.arms) |arm| {
                    try self.checkExpr(arm.body);
                }
            },
            .return_stmt => |return_stmt| {
                if (return_stmt.value) |expr| {
                    try self.checkExpr(expr);
                }
            },
            .assign_stmt => |as| {
                try self.checkExpr(as.value);
            },
            .defer_stmt => |expr| {
                try self.checkExpr(expr);
                if (expr.* == .call) {
                    const call = expr.call;
                    if (call.callee.* == .field_access) {
                        const fa = call.callee.field_access;
                        if (std.mem.eql(u8, fa.field, "dispose")) {
                            if (fa.object.* == .identifier) {
                                const region_name = fa.object.identifier.name;
                                for (self.active_regions.items) |*region| {
                                    if (std.mem.eql(u8, region.name, region_name)) {
                                        region.is_disposed = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn checkExpr(self: *RegionChecker, expr: *ast.Expr) !void {
        switch (expr.*) {
            .call => |ce| {
                try self.checkExpr(ce.callee);
                for (ce.args) |arg| {
                    try self.checkExpr(arg);
                }
            },
            .binary => |be| {
                try self.checkExpr(be.left);
                try self.checkExpr(be.right);
            },
            .unary => |ue| {
                try self.checkExpr(ue.operand);
            },
            .field_access => |fa| {
                try self.checkExpr(fa.object);
            },
            .ok => |ok_expr| {
                try self.checkExpr(ok_expr);
            },
            .check => |ce| {
                try self.checkExpr(ce.expr);
            },
            .ensure => |ee| {
                try self.checkExpr(ee.condition);
            },
            .match_expr => |me| {
                try self.checkExpr(me.value);
                for (me.arms) |arm| {
                    try self.checkExpr(arm.body);
                }
            },
            else => {},
        }
    }

    pub fn isRegionType(self: *RegionChecker, type_annotation: ast.Type) bool {
        _ = self;
        if (type_annotation != .simple) return false;
        const type_name = type_annotation.simple.name;
        return std.mem.eql(u8, type_name, "Region");
    }

    fn checkRegionsAtScopeExit(self: *RegionChecker) !void {
        var i = self.active_regions.items.len;
        while (i > 0) {
            i -= 1;
            const region = self.active_regions.items[i];
            if (region.scope_level >= self.current_scope_level) {
                if (!region.is_disposed) {
                    try self.diagnostics_list.addWarning(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "region '{s}' escapes its scope without being disposed",
                            .{region.name},
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = region.name.len,
                        },
                        try self.allocator.dupe(u8, "use 'defer region.dispose()' to ensure proper cleanup"),
                    );
                }
                _ = self.active_regions.orderedRemove(i);
            }
        }
    }
};

test {
    _ = @import("region_checker_test.zig");
}
