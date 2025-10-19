const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const TypedExpr = struct {
    expr: *ast.Expr,
    resolved_type: types.ResolvedType,
    effects: []types.Effect,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TypedExpr) void {
        self.resolved_type.deinit(self.allocator);
        self.allocator.free(self.effects);
    }
};

pub const TypedStmt = struct {
    stmt: ast.Stmt,
    type_info: ?types.ResolvedType,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TypedStmt) void {
        if (self.type_info) |*ti| {
            ti.deinit(self.allocator);
        }
    }
};

pub const TypedModule = struct {
    statements: []TypedStmt,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TypedModule) void {
        for (self.statements) |*stmt| {
            stmt.deinit();
        }
        self.allocator.free(self.statements);
    }
};
