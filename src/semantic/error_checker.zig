const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");

pub const ErrorChecker = struct {
    symbols: *symbol_table.SymbolTable,
    domains: *error_domains.ErrorDomainTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        symbols: *symbol_table.SymbolTable,
        domains: *error_domains.ErrorDomainTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) ErrorChecker {
        return .{
            .symbols = symbols,
            .domains = domains,
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
        };
    }

    pub fn checkModule(self: *ErrorChecker, module: ast.Module) !void {
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.checkFunction(stmt.function_decl);
            }
        }
    }

    pub fn checkFunction(self: *ErrorChecker, func: ast.FunctionDecl) !void {
        if (func.error_domain) |domain_name| {
            if (self.domains.get(domain_name) == null) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "unknown error domain '{s}'",
                        .{domain_name},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = domain_name.len,
                    },
                    null,
                );
                return;
            }

            for (func.body) |stmt| {
                try self.checkStmtErrors(stmt, domain_name);
            }
        }
    }

    fn checkStmtErrors(self: *ErrorChecker, stmt: ast.Stmt, current_domain: []const u8) std.mem.Allocator.Error!void {
        switch (stmt) {
            .expr_stmt => |expr| try self.checkExprErrors(expr, current_domain),
            .return_stmt => |return_stmt| {
                if (return_stmt.value) |expr| {
                    try self.checkExprErrors(expr, current_domain);
                }
            },
            .if_stmt => |is| {
                try self.checkExprErrors(is.condition, current_domain);
                for (is.then_block) |then_stmt| {
                    try self.checkStmtErrors(then_stmt, current_domain);
                }
                if (is.else_block) |else_block| {
                    for (else_block) |else_stmt| {
                        try self.checkStmtErrors(else_stmt, current_domain);
                    }
                }
            },
            .while_stmt => |ws| {
                try self.checkExprErrors(ws.condition, current_domain);
                for (ws.body) |body_stmt| {
                    try self.checkStmtErrors(body_stmt, current_domain);
                }
            },
            .for_stmt => |fs| {
                try self.checkExprErrors(fs.iterable, current_domain);
                for (fs.body) |body_stmt| {
                    try self.checkStmtErrors(body_stmt, current_domain);
                }
            },
            .match_stmt => |ms| {
                try self.checkExprErrors(ms.value, current_domain);
                for (ms.arms) |arm| {
                    try self.checkExprErrors(arm.body, current_domain);
                }
            },
            .assign_stmt => |as| {
                try self.checkExprErrors(as.value, current_domain);
            },
            .var_decl => |vd| {
                try self.checkExprErrors(vd.value, current_domain);
            },
            .const_decl => |cd| {
                try self.checkExprErrors(cd.value, current_domain);
            },
            else => {},
        }
    }

    fn checkExprErrors(self: *ErrorChecker, expr: *ast.Expr, current_domain: []const u8) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .err => |ee| try self.checkErrConstruction(ee, current_domain),
            .check => |ce| try self.checkCheckExpr(ce, current_domain),
            .ensure => |ee| try self.checkEnsureExpr(ee, current_domain),
            .call => |ce| {
                try self.checkExprErrors(ce.callee, current_domain);
                for (ce.args) |arg| {
                    try self.checkExprErrors(arg, current_domain);
                }
            },
            .binary => |be| {
                try self.checkExprErrors(be.left, current_domain);
                try self.checkExprErrors(be.right, current_domain);
            },
            .unary => |ue| {
                try self.checkExprErrors(ue.operand, current_domain);
            },
            .field_access => |fa| {
                try self.checkExprErrors(fa.object, current_domain);
            },
            .array_literal => |al| {
                for (al.elements) |elem| {
                    try self.checkExprErrors(elem, current_domain);
                }
            },
            .ok => |ok_expr| {
                try self.checkExprErrors(ok_expr, current_domain);
            },
            .match_expr => |me| {
                try self.checkExprErrors(me.value, current_domain);
                for (me.arms) |arm| {
                    try self.checkExprErrors(arm.body, current_domain);
                }
            },
            else => {},
        }
    }

    fn checkErrConstruction(self: *ErrorChecker, err_expr: ast.ErrorExpr, current_domain: []const u8) std.mem.Allocator.Error!void {
        if (self.domains.get(current_domain)) |domain| {
            if (domain.findVariant(err_expr.variant) == null) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "variant '{s}' does not exist in error domain '{s}'",
                        .{ err_expr.variant, current_domain },
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = err_expr.variant.len,
                    },
                    null,
                );
            }
        }
    }

    fn checkCheckExpr(self: *ErrorChecker, check_expr: ast.CheckExpr, current_domain: []const u8) std.mem.Allocator.Error!void {
        try self.checkExprErrors(check_expr.expr, current_domain);
    }

    fn checkEnsureExpr(self: *ErrorChecker, ensure_expr: ast.EnsureExpr, current_domain: []const u8) std.mem.Allocator.Error!void {
        try self.checkExprErrors(ensure_expr.condition, current_domain);
        try self.checkErrConstruction(ensure_expr.error_expr, current_domain);
    }
};

test {
    _ = @import("error_checker_test.zig");
}
