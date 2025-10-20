const std = @import("std");
const ast = @import("ast.zig");

pub const Printer = struct {
    writer: std.fs.File.Writer,
    indent_level: usize,

    pub fn init(writer: std.fs.File.Writer) Printer {
        return .{
            .writer = writer,
            .indent_level = 0,
        };
    }

    pub fn printModule(self: *Printer, module: ast.Module) !void {
        if (module.package_decl) |pkg| {
            try self.printPackageDecl(pkg);
            try self.writer.writeAll("\n");
        }

        for (module.imports) |imp| {
            try self.printImportDecl(imp);
            try self.writer.writeAll("\n");
        }

        if (module.imports.len > 0) {
            try self.writer.writeAll("\n");
        }

        for (module.statements) |stmt| {
            try self.printStmt(stmt);
            try self.writer.writeAll("\n");
        }
    }

    fn printPackageDecl(self: *Printer, pkg: ast.PackageDecl) !void {
        try self.writer.print("package {s};", .{pkg.name});
    }

    fn printImportDecl(self: *Printer, imp: ast.ImportDecl) !void {
        try self.writer.print("import {s} {{ ", .{imp.source});

        for (imp.items, 0..) |item, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.writer.writeAll(item.name);
            if (item.alias) |alias| {
                try self.writer.print(" as {s}", .{alias});
            }
        }

        try self.writer.writeAll(" }");

        if (imp.capability) |cap| {
            try self.writer.print(" using capability {s}", .{cap});
        }

        try self.writer.writeAll(";");
    }

    fn printStmt(self: *Printer, stmt: ast.Stmt) !void {
        switch (stmt) {
            .const_decl => |decl| {
                try self.indent();
                try self.writer.print("const {s}", .{decl.name});
                if (decl.type_annotation) |t| {
                    try self.writer.writeAll(": ");
                    try self.printType(t);
                }
                try self.writer.writeAll(" = ");
                try self.printExpr(decl.value);
                try self.writer.writeAll(";");
            },
            .var_decl => |decl| {
                try self.indent();
                try self.writer.print("var {s}", .{decl.name});
                if (decl.type_annotation) |t| {
                    try self.writer.writeAll(": ");
                    try self.printType(t);
                }
                try self.writer.writeAll(" = ");
                try self.printExpr(decl.value);
                try self.writer.writeAll(";");
            },
            .function_decl => |decl| {
                try self.indent();
                try self.writer.print("function {s}(", .{decl.name});

                for (decl.params, 0..) |param, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    if (param.is_capability) try self.writer.writeAll("cap ");
                    if (param.is_inout) try self.writer.writeAll("inout ");
                    try self.writer.print("{s}: ", .{param.name});
                    try self.printType(param.type_annotation);
                }

                try self.writer.writeAll(") -> ");
                try self.printType(decl.return_type);

                if (decl.error_domain) |domain| {
                    try self.writer.print(" error {s}", .{domain});
                }

                if (decl.effects.len > 0) {
                    try self.writer.writeAll(" effects [");
                    for (decl.effects, 0..) |effect, i| {
                        if (i > 0) try self.writer.writeAll(", ");
                        try self.writer.writeAll(effect);
                    }
                    try self.writer.writeAll("]");
                }

                try self.writer.writeAll(" {\n");
                self.indent_level += 1;

                for (decl.body) |body_stmt| {
                    try self.printStmt(body_stmt);
                    try self.writer.writeAll("\n");
                }

                self.indent_level -= 1;
                try self.indent();
                try self.writer.writeAll("}");
            },
            .type_decl => |decl| {
                try self.indent();
                try self.writer.print("type {s} = ", .{decl.name});
                try self.printType(decl.type_expr);
                try self.writer.writeAll(";");
            },
            .domain_decl => |decl| {
                try self.indent();
                try self.writer.print("domain {s} {{\n", .{decl.name});
                self.indent_level += 1;

                for (decl.variants) |variant| {
                    try self.indent();
                    try self.writer.writeAll(variant.name);

                    if (variant.fields.len > 0) {
                        try self.writer.writeAll(" { ");
                        for (variant.fields, 0..) |field, i| {
                            if (i > 0) try self.writer.writeAll(", ");
                            try self.writer.print("{s}: ", .{field.name});
                            try self.printType(field.type_annotation);
                        }
                        try self.writer.writeAll(" }");
                    }

                    try self.writer.writeAll("\n");
                }

                self.indent_level -= 1;
                try self.indent();
                try self.writer.writeAll("}");
            },
            .role_decl => |decl| {
                try self.indent();
                try self.writer.print("role {s};", .{decl.name});
            },
            .return_stmt => |expr| {
                try self.indent();
                try self.writer.writeAll("return");
                if (expr) |e| {
                    try self.writer.writeAll(" ");
                    try self.printExpr(e);
                }
                try self.writer.writeAll(";");
            },
            .defer_stmt => |expr| {
                try self.indent();
                try self.writer.writeAll("defer ");
                try self.printExpr(expr);
                try self.writer.writeAll(";");
            },
            .expr_stmt => |expr| {
                try self.indent();
                try self.printExpr(expr);
                try self.writer.writeAll(";");
            },
            .if_stmt => |stmt_data| {
                try self.indent();
                try self.writer.writeAll("if ");
                try self.printExpr(stmt_data.condition);
                try self.writer.writeAll(" {\n");

                self.indent_level += 1;
                for (stmt_data.then_block) |then_stmt| {
                    try self.printStmt(then_stmt);
                    try self.writer.writeAll("\n");
                }
                self.indent_level -= 1;

                try self.indent();
                try self.writer.writeAll("}");

                if (stmt_data.else_block) |else_block| {
                    try self.writer.writeAll(" else {\n");
                    self.indent_level += 1;
                    for (else_block) |else_stmt| {
                        try self.printStmt(else_stmt);
                        try self.writer.writeAll("\n");
                    }
                    self.indent_level -= 1;
                    try self.indent();
                    try self.writer.writeAll("}");
                }
            },
            .while_stmt => |stmt_data| {
                try self.indent();
                try self.writer.writeAll("while ");
                try self.printExpr(stmt_data.condition);
                try self.writer.writeAll(" {\n");

                self.indent_level += 1;
                for (stmt_data.body) |body_stmt| {
                    try self.printStmt(body_stmt);
                    try self.writer.writeAll("\n");
                }
                self.indent_level -= 1;

                try self.indent();
                try self.writer.writeAll("}");
            },
            .for_stmt => |stmt_data| {
                try self.indent();
                try self.writer.print("for {s} in ", .{stmt_data.iterator});
                try self.printExpr(stmt_data.iterable);
                try self.writer.writeAll(" {\n");

                self.indent_level += 1;
                for (stmt_data.body) |body_stmt| {
                    try self.printStmt(body_stmt);
                    try self.writer.writeAll("\n");
                }
                self.indent_level -= 1;

                try self.indent();
                try self.writer.writeAll("}");
            },
            .match_stmt => |stmt_data| {
                try self.indent();
                try self.writer.writeAll("match ");
                try self.printExpr(stmt_data.value);
                try self.writer.writeAll(" {\n");

                self.indent_level += 1;
                for (stmt_data.arms) |arm| {
                    try self.indent();
                    try self.printPattern(arm.pattern);
                    try self.writer.writeAll(" -> ");
                    try self.printExpr(arm.body);
                    try self.writer.writeAll(";\n");
                }
                self.indent_level -= 1;

                try self.indent();
                try self.writer.writeAll("}");
            },
            .break_stmt => {
                try self.indent();
                try self.writer.writeAll("break;");
            },
            .continue_stmt => {
                try self.indent();
                try self.writer.writeAll("continue;");
            },
            .use_error => |domain| {
                try self.indent();
                try self.writer.print("use error {s};", .{domain});
            },
            .package_decl => |pkg| {
                try self.printPackageDecl(pkg);
            },
            .import_decl => |imp| {
                try self.printImportDecl(imp);
            },
        }
    }

    fn printExpr(self: *Printer, expr: *const ast.Expr) !void {
        switch (expr.*) {
            .number => |n| try self.writer.writeAll(n),
            .string => |s| try self.writer.writeAll(s),
            .char => |c| try self.writer.writeAll(c),
            .identifier => |id| try self.writer.writeAll(id.name),
            .bool_literal => |b| try self.writer.writeAll(if (b) "true" else "false"),
            .null_literal => try self.writer.writeAll("null"),
            .binary => |bin| {
                try self.printExpr(bin.left);
                try self.writer.writeAll(" ");
                try self.writer.writeAll(switch (bin.op) {
                    .add => "+",
                    .subtract => "-",
                    .multiply => "*",
                    .divide => "/",
                    .modulo => "%",
                    .eq => "===",
                    .ne => "!==",
                    .lt => "<",
                    .gt => ">",
                    .le => "<=",
                    .ge => ">=",
                    .logical_and => "&&",
                    .logical_or => "||",
                    .bitwise_and => "&",
                    .bitwise_or => "|",
                    .bitwise_xor => "^",
                    .shift_left => "<<",
                    .shift_right => ">>",
                });
                try self.writer.writeAll(" ");
                try self.printExpr(bin.right);
            },
            .unary => |un| {
                try self.writer.writeAll(switch (un.op) {
                    .negate => "-",
                    .not => "!",
                    .bitwise_not => "~",
                });
                try self.printExpr(un.operand);
            },
            .call => |call| {
                try self.printExpr(call.callee);
                try self.writer.writeAll("(");
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    try self.printExpr(arg);
                }
                try self.writer.writeAll(")");
            },
            .field_access => |field| {
                try self.printExpr(field.object);
                try self.writer.print(".{s}", .{field.field});
            },
            .ok => |value| {
                try self.writer.writeAll("ok ");
                try self.printExpr(value);
            },
            .err => |err_expr| {
                try self.writer.print("err {s}", .{err_expr.variant});
                if (err_expr.fields.len > 0) {
                    try self.writer.writeAll(" { ");
                    for (err_expr.fields, 0..) |field, i| {
                        if (i > 0) try self.writer.writeAll(", ");
                        try self.writer.print("{s}: ", .{field.name});
                        try self.printType(field.type_annotation);
                    }
                    try self.writer.writeAll(" }");
                }
            },
            .check => |check| {
                try self.writer.writeAll("check ");
                try self.printExpr(check.expr);
            },
            .ensure => |ensure| {
                try self.writer.writeAll("ensure ");
                try self.printExpr(ensure.condition);
                try self.writer.writeAll(" else err ");
                try self.writer.writeAll(ensure.error_expr.variant);
            },
            .match_expr => |match| {
                try self.writer.writeAll("match ");
                try self.printExpr(match.value);
                try self.writer.writeAll(" { ");
                for (match.arms, 0..) |arm, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    try self.printPattern(arm.pattern);
                    try self.writer.writeAll(" -> ");
                    try self.printExpr(arm.body);
                }
                try self.writer.writeAll(" }");
            },
        }
    }

    fn printType(self: *Printer, type_expr: ast.Type) !void {
        switch (type_expr) {
            .simple => |s| try self.writer.writeAll(s.name),
            .generic => |gen| {
                try self.writer.writeAll(gen.name);
                try self.writer.writeAll("<");
                for (gen.type_args, 0..) |arg, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    try self.printType(arg);
                }
                try self.writer.writeAll(">");
            },
            .array => |arr| {
                try self.writer.writeAll("Array<");
                try self.printType(arr.element_type.*);
                try self.writer.writeAll(", ");
                try self.printExpr(arr.size);
                try self.writer.writeAll(">");
            },
            .vector => |vec| {
                try self.writer.writeAll("Vector<");
                try self.printType(vec.element_type.*);
                try self.writer.writeAll(", ");
                try self.printExpr(vec.size);
                try self.writer.writeAll(">");
            },
            .view => |view| {
                try self.writer.writeAll("View<");
                if (view.mutable) try self.writer.writeAll("mut ");
                try self.printType(view.element_type.*);
                try self.writer.writeAll(">");
            },
            .nullable => |inner| {
                try self.printType(inner.*);
                try self.writer.writeAll("?");
            },
            .function_type => |func| {
                try self.writer.writeAll("(");
                for (func.params, 0..) |param, i| {
                    if (i > 0) try self.writer.writeAll(", ");
                    try self.printType(param);
                }
                try self.writer.writeAll(") -> ");
                try self.printType(func.return_type.*);

                if (func.error_domain) |domain| {
                    try self.writer.print(" error {s}", .{domain});
                }

                if (func.effects.len > 0) {
                    try self.writer.writeAll(" effects [");
                    for (func.effects, 0..) |effect, i| {
                        if (i > 0) try self.writer.writeAll(", ");
                        try self.writer.writeAll(effect);
                    }
                    try self.writer.writeAll("]");
                }
            },
        }
    }

    fn printPattern(self: *Printer, pattern: ast.Pattern) !void {
        switch (pattern) {
            .wildcard => try self.writer.writeAll("_"),
            .identifier => |id| try self.writer.writeAll(id),
            .number => |n| try self.writer.writeAll(n),
            .string => |s| try self.writer.writeAll(s),
            .variant => |v| {
                try self.writer.writeAll(v.name);
                if (v.fields) |fields| {
                    try self.writer.writeAll(" { ");
                    for (fields, 0..) |field, i| {
                        if (i > 0) try self.writer.writeAll(", ");
                        try self.printPattern(field);
                    }
                    try self.writer.writeAll(" }");
                }
            },
        }
    }

    fn indent(self: *Printer) !void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.writer.writeAll("  ");
        }
    }
};
