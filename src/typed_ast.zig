const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const TypedExpr = struct {
    expr: *ast.Expr,
    resolved_type: types.ResolvedType,
    effects: []types.Effect,
    allocator: std.mem.Allocator,

    // types are interned via CompilationContext; only effects need explicit cleanup
    pub fn deinit(self: *TypedExpr) void {
        self.allocator.free(self.effects);
    }
};

pub const TypedStmt = struct {
    stmt: ast.Stmt,
    type_info: ?types.ResolvedType,
    allocator: std.mem.Allocator,

    // types are arena-managed, no cleanup needed
    pub fn deinit(self: *TypedStmt) void {
        _ = self;
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
