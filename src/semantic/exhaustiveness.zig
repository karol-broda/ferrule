const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const error_domains = @import("../error_domains.zig");
const diagnostics = @import("../diagnostics.zig");

pub const ExhaustivenessChecker = struct {
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
    ) ExhaustivenessChecker {
        return .{
            .symbols = symbols,
            .domains = domains,
            .diagnostics_list = diagnostics_list,
            .allocator = allocator,
            .source_file = source_file,
        };
    }

    pub fn checkModule(self: *ExhaustivenessChecker, module: ast.Module) !void {
        for (module.statements) |stmt| {
            try self.checkStmt(stmt);
        }
    }

    pub fn checkStmt(self: *ExhaustivenessChecker, stmt: ast.Stmt) !void {
        switch (stmt) {
            .match_stmt => |ms| try self.checkMatch(ms),
            .function_decl => |fd| {
                for (fd.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .if_stmt => |is| {
                for (is.then_block) |then_stmt| {
                    try self.checkStmt(then_stmt);
                }
                if (is.else_block) |else_block| {
                    for (else_block) |else_stmt| {
                        try self.checkStmt(else_stmt);
                    }
                }
            },
            .while_stmt => |ws| {
                for (ws.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .for_stmt => |fs| {
                for (fs.body) |body_stmt| {
                    try self.checkStmt(body_stmt);
                }
            },
            .expr_stmt => |expr| try self.checkExpr(expr),
            else => {},
        }
    }

    fn checkExpr(self: *ExhaustivenessChecker, expr: *ast.Expr) !void {
        switch (expr.*) {
            .match_expr => |me| try self.checkMatchExpr(me),
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
            else => {},
        }
    }

    pub fn checkMatch(self: *ExhaustivenessChecker, match_stmt: ast.MatchStmt) !void {
        var covered_patterns = std.StringHashMap(void).init(self.allocator);
        defer covered_patterns.deinit();

        var has_wildcard = false;

        for (match_stmt.arms) |arm| {
            switch (arm.pattern) {
                .wildcard => has_wildcard = true,
                .identifier => has_wildcard = true,
                .variant => |v| {
                    try covered_patterns.put(v.name, {});
                },
                else => {},
            }
        }

        if (!has_wildcard) {
            try self.diagnostics_list.addWarning(
                try self.allocator.dupe(u8, "match statement may not be exhaustive"),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                try self.allocator.dupe(u8, "consider adding a wildcard pattern '_' to handle all cases"),
            );
        }
    }

    pub fn checkMatchExpr(self: *ExhaustivenessChecker, match_expr: ast.MatchExpr) !void {
        var covered_patterns = std.StringHashMap(void).init(self.allocator);
        defer covered_patterns.deinit();

        var has_wildcard = false;

        for (match_expr.arms) |arm| {
            switch (arm.pattern) {
                .wildcard => has_wildcard = true,
                .identifier => has_wildcard = true,
                .variant => |v| {
                    try covered_patterns.put(v.name, {});
                },
                else => {},
            }
        }

        if (!has_wildcard) {
            try self.diagnostics_list.addWarning(
                try self.allocator.dupe(u8, "match expression may not be exhaustive"),
                .{
                    .file = self.source_file,
                    .line = 0,
                    .column = 0,
                    .length = 0,
                },
                try self.allocator.dupe(u8, "consider adding a wildcard pattern '_' to handle all cases"),
            );
        }
    }

    pub fn checkDomainExhaustiveness(
        self: *ExhaustivenessChecker,
        arms: []ast.MatchArm,
        domain_name: []const u8,
    ) !bool {
        if (self.domains.get(domain_name)) |domain| {
            var covered = std.StringHashMap(void).init(self.allocator);
            defer covered.deinit();

            var has_wildcard = false;

            for (arms) |arm| {
                switch (arm.pattern) {
                    .wildcard => has_wildcard = true,
                    .identifier => has_wildcard = true,
                    .variant => |v| {
                        try covered.put(v.name, {});
                    },
                    else => {},
                }
            }

            if (has_wildcard) return true;

            for (domain.variants) |variant| {
                if (!covered.contains(variant.name)) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "match is not exhaustive: missing case for variant '{s}'",
                            .{variant.name},
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = 0,
                        },
                        try self.allocator.dupe(u8, "add a case for this variant or use a wildcard '_' pattern"),
                    );
                    return false;
                }
            }

            return true;
        }

        return false;
    }
};

test {
    _ = @import("exhaustiveness_test.zig");
}
