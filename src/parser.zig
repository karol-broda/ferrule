const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    OutOfMemory,
    InvalidSyntax,
};

pub const Parser = struct {
    tokens: []const Token,
    current: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) ParseError!ast.Module {
        var package_decl: ?ast.PackageDecl = null;
        var imports: std.ArrayList(ast.ImportDecl) = .empty;
        var statements: std.ArrayList(ast.Stmt) = .empty;

        errdefer {
            if (package_decl) |pd| {
                self.allocator.free(pd.name);
            }
            for (imports.items) |import_decl| {
                import_decl.deinit(self.allocator);
            }
            imports.deinit(self.allocator);
            for (statements.items) |*stmt| {
                ast.deinitStmt(stmt, self.allocator);
            }
            statements.deinit(self.allocator);
        }

        // parse package declaration
        if (self.check(.package_kw)) {
            package_decl = try self.packageDeclaration();
        }

        // parse imports
        while (self.check(.import_kw)) {
            const import_decl = try self.importDeclaration();
            imports.append(self.allocator, import_decl) catch |err| {
                import_decl.deinit(self.allocator);
                return err;
            };
        }

        // parse top-level declarations
        while (!self.isAtEnd()) {
            const decl = try self.declaration();
            statements.append(self.allocator, decl) catch |err| {
                ast.deinitStmt(&decl, self.allocator);
                return err;
            };
        }

        return ast.Module{
            .package_decl = package_decl,
            .imports = try imports.toOwnedSlice(self.allocator),
            .statements = try statements.toOwnedSlice(self.allocator),
        };
    }

    fn packageDeclaration(self: *Parser) ParseError!ast.PackageDecl {
        _ = try self.consume(.package_kw, "expected 'package'");

        // handle dotted package names like "example.hello" or "test.error"
        var name_parts: std.ArrayList(u8) = .empty;
        defer name_parts.deinit(self.allocator);

        const first_part = try self.consumeIdentifierOrKeyword("expected package name");
        try name_parts.appendSlice(self.allocator, first_part.lexeme);

        while (self.match(.dot)) {
            try name_parts.append(self.allocator, '.');
            const next_part = try self.consumeIdentifierOrKeyword("expected identifier after '.'");
            try name_parts.appendSlice(self.allocator, next_part.lexeme);
        }

        const full_name = try name_parts.toOwnedSlice(self.allocator);

        _ = try self.consume(.semicolon, "expected ';' after package declaration");

        return ast.PackageDecl{
            .name = full_name,
        };
    }

    fn importDeclaration(self: *Parser) ParseError!ast.ImportDecl {
        _ = try self.consume(.import_kw, "expected 'import'");
        const source = try self.consume(.identifier, "expected import source");

        _ = try self.consume(.lbrace, "expected '{' after import source");

        var items: std.ArrayList(ast.ImportItem) = .empty;
        errdefer items.deinit(self.allocator);

        if (!self.check(.rbrace)) {
            while (true) {
                const item_name = try self.consume(.identifier, "expected import item name");
                var alias: ?[]const u8 = null;

                if (self.match(.as_kw)) {
                    const alias_token = try self.consume(.identifier, "expected alias name");
                    alias = alias_token.lexeme;
                }

                items.append(self.allocator, ast.ImportItem{
                    .name = item_name.lexeme,
                    .alias = alias,
                }) catch |err| {
                    return err;
                };

                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.rbrace, "expected '}' after import items");

        var capability: ?[]const u8 = null;
        if (self.match(.using_kw)) {
            _ = try self.consume(.capability_kw, "expected 'capability' after 'using'");
            const cap_token = try self.consume(.identifier, "expected capability name");
            capability = cap_token.lexeme;
        }

        _ = try self.consume(.semicolon, "expected ';' after import declaration");

        return ast.ImportDecl{
            .source = source.lexeme,
            .items = try items.toOwnedSlice(self.allocator),
            .capability = capability,
        };
    }

    fn declaration(self: *Parser) ParseError!ast.Stmt {
        if (self.match(.function_kw)) return try self.functionDeclaration();
        if (self.match(.type_kw)) return try self.typeDeclaration();
        if (self.match(.error_kw)) return try self.errorDeclaration();
        if (self.match(.domain_kw)) return try self.domainDeclaration();
        if (self.match(.use_kw)) return try self.useErrorDeclaration();

        return try self.statement();
    }

    fn useErrorDeclaration(self: *Parser) ParseError!ast.Stmt {
        _ = try self.consume(.error_kw, "expected 'error' after 'use'");
        const domain = try self.consume(.identifier, "expected error domain name");
        _ = try self.consume(.semicolon, "expected ';' after use error declaration");

        return ast.Stmt{ .use_error = domain.lexeme };
    }

    fn errorDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected error name");

        var fields: std.ArrayList(ast.Field) = .empty;
        errdefer {
            for (fields.items) |field| {
                ast.deinitType(&field.type_annotation, self.allocator);
            }
            fields.deinit(self.allocator);
        }

        if (self.match(.lbrace)) {
            if (!self.check(.rbrace)) {
                while (true) {
                    const field_name = try self.consume(.identifier, "expected field name");
                    _ = try self.consume(.colon, "expected ':' after field name");
                    const field_type = try self.parseType();

                    fields.append(self.allocator, ast.Field{
                        .name = field_name.lexeme,
                        .type_annotation = field_type,
                    }) catch |err| {
                        ast.deinitType(&field_type, self.allocator);
                        return err;
                    };

                    if (!self.match(.comma)) break;
                }
            }
            _ = try self.consume(.rbrace, "expected '}' after error fields");
        }

        _ = try self.consume(.semicolon, "expected ';' after error declaration");

        return ast.Stmt{
            .error_decl = ast.ErrorDecl{
                .name = name.lexeme,
                .fields = try fields.toOwnedSlice(self.allocator),
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn functionDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected function name");

        // parse optional type parameters <T, U>
        var type_params: ?[]ast.TypeParam = null;
        if (self.match(.lt)) {
            var tparams: std.ArrayList(ast.TypeParam) = .empty;
            errdefer tparams.deinit(self.allocator);

            while (true) {
                var variance: ast.Variance = .invariant;
                var is_const = false;
                var const_type: ?ast.Type = null;

                if (self.match(.in_kw)) {
                    variance = .contravariant;
                } else if (self.match(.out_kw)) {
                    variance = .covariant;
                } else if (self.match(.const_kw)) {
                    is_const = true;
                }

                const param_name = try self.consume(.identifier, "expected type parameter name");

                if (is_const) {
                    _ = try self.consume(.colon, "expected ':' after const parameter name");
                    const_type = try self.parseType();
                }

                var constraint: ?ast.Type = null;
                if (!is_const and self.match(.colon)) {
                    constraint = try self.parseType();
                }

                try tparams.append(self.allocator, ast.TypeParam{
                    .name = param_name.lexeme,
                    .variance = variance,
                    .constraint = constraint,
                    .is_const = is_const,
                    .const_type = const_type,
                });

                if (!self.match(.comma)) break;
            }

            _ = try self.consume(.gt, "expected '>' after type parameters");
            type_params = try tparams.toOwnedSlice(self.allocator);
        }

        _ = try self.consume(.lparen, "expected '(' after function name");

        var params: std.ArrayList(ast.Param) = .empty;
        errdefer {
            for (params.items) |*param| {
                ast.deinitType(&param.type_annotation, self.allocator);
            }
            params.deinit(self.allocator);
        }

        if (!self.check(.rparen)) {
            while (true) {
                var is_capability = false;
                var is_inout = false;

                if (self.match(.cap_kw)) {
                    is_capability = true;
                }

                if (self.match(.inout_kw)) {
                    is_inout = true;
                }

                const param_name = try self.consume(.identifier, "expected parameter name");
                _ = try self.consume(.colon, "expected ':' after parameter name");
                const param_type = try self.parseType();

                params.append(self.allocator, ast.Param{
                    .name = param_name.lexeme,
                    .type_annotation = param_type,
                    .is_inout = is_inout,
                    .is_capability = is_capability,
                    .name_loc = .{ .line = param_name.line, .column = param_name.column },
                }) catch |err| {
                    ast.deinitType(&param_type, self.allocator);
                    return err;
                };

                if (!self.match(.comma)) break;
            }
        }

        const rparen_result = self.consume(.rparen, "expected ')' after parameters") catch |err| {
            return err;
        };
        _ = rparen_result;
        _ = try self.consume(.arrow, "expected '->' after parameters");

        const return_type = try self.parseType();
        errdefer ast.deinitType(&return_type, self.allocator);

        var error_domain: ?[]const u8 = null;
        if (self.match(.error_kw)) {
            const err_token = try self.consume(.identifier, "expected error domain name");
            error_domain = err_token.lexeme;
        }

        var effects: std.ArrayList([]const u8) = .empty;
        errdefer effects.deinit(self.allocator);

        if (self.match(.effects_kw)) {
            _ = try self.consume(.lbracket, "expected '[' after 'effects'");
            if (!self.check(.rbracket)) {
                while (true) {
                    const effect = try self.consume(.identifier, "expected effect name");
                    effects.append(self.allocator, effect.lexeme) catch |err| {
                        return err;
                    };
                    if (!self.match(.comma)) break;
                }
            }
            _ = try self.consume(.rbracket, "expected ']' after effects");
        }

        _ = try self.consume(.lbrace, "expected '{' before function body");
        const body = self.block() catch |err| {
            return err;
        };

        return ast.Stmt{
            .function_decl = ast.FunctionDecl{
                .name = name.lexeme,
                .type_params = type_params,
                .params = try params.toOwnedSlice(self.allocator),
                .return_type = return_type,
                .error_domain = error_domain,
                .effects = try effects.toOwnedSlice(self.allocator),
                .body = body,
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn typeDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected type name");

        // Parse optional type parameters <T, U>
        var type_params: ?[]ast.TypeParam = null;
        if (self.match(.lt)) {
            var params: std.ArrayList(ast.TypeParam) = .empty;
            errdefer params.deinit(self.allocator);

            while (true) {
                var variance: ast.Variance = .invariant;
                var is_const = false;
                var const_type: ?ast.Type = null;

                if (self.match(.in_kw)) {
                    variance = .contravariant;
                } else if (self.match(.out_kw)) {
                    variance = .covariant;
                } else if (self.match(.const_kw)) {
                    is_const = true;
                }

                const param_name = try self.consume(.identifier, "expected type parameter name");

                if (is_const) {
                    _ = try self.consume(.colon, "expected ':' after const parameter name");
                    const_type = try self.parseType();
                }

                var constraint: ?ast.Type = null;
                if (!is_const and self.match(.colon)) {
                    constraint = try self.parseType();
                }

                try params.append(self.allocator, ast.TypeParam{
                    .name = param_name.lexeme,
                    .variance = variance,
                    .constraint = constraint,
                    .is_const = is_const,
                    .const_type = const_type,
                });

                if (!self.match(.comma)) break;
            }

            _ = try self.consume(.gt, "expected '>' after type parameters");
            type_params = try params.toOwnedSlice(self.allocator);
        }

        _ = try self.consume(.eq, "expected '=' after type name");
        const type_expr = try self.parseType();
        _ = try self.consume(.semicolon, "expected ';' after type declaration");

        return ast.Stmt{
            .type_decl = ast.TypeDecl{
                .name = name.lexeme,
                .type_params = type_params,
                .type_expr = type_expr,
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn domainDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected domain name");

        // Check for union syntax: domain IoError = NotFound | Denied;
        if (self.match(.eq)) {
            var error_names: std.ArrayList([]const u8) = .empty;
            errdefer error_names.deinit(self.allocator);

            // First error name
            const first_name = try self.consume(.identifier, "expected error type name");
            try error_names.append(self.allocator, first_name.lexeme);

            // Additional error names after |
            while (self.match(.pipe)) {
                const err_name = try self.consume(.identifier, "expected error type name after '|'");
                try error_names.append(self.allocator, err_name.lexeme);
            }

            _ = try self.consume(.semicolon, "expected ';' after domain declaration");

            return ast.Stmt{
                .domain_decl = ast.DomainDecl{
                    .name = name.lexeme,
                    .error_union = try error_names.toOwnedSlice(self.allocator),
                    .variants = null,
                    .name_loc = .{ .line = name.line, .column = name.column },
                },
            };
        }

        // Inline variant syntax: domain IoError { NotFound { path: String } ... }
        _ = try self.consume(.lbrace, "expected '{' or '=' after domain name");

        var variants: std.ArrayList(ast.DomainVariant) = .empty;
        errdefer {
            for (variants.items) |variant| {
                for (variant.fields) |field| {
                    ast.deinitType(&field.type_annotation, self.allocator);
                }
                self.allocator.free(variant.fields);
            }
            variants.deinit(self.allocator);
        }

        while (!self.check(.rbrace) and !self.isAtEnd()) {
            const variant_name = try self.consume(.identifier, "expected variant name");

            var fields: std.ArrayList(ast.Field) = .empty;
            errdefer {
                for (fields.items) |field| {
                    ast.deinitType(&field.type_annotation, self.allocator);
                }
                fields.deinit(self.allocator);
            }

            if (self.match(.lbrace)) {
                if (!self.check(.rbrace)) {
                    while (true) {
                        const field_name = try self.consume(.identifier, "expected field name");
                        _ = try self.consume(.colon, "expected ':' after field name");
                        const field_type = try self.parseType();

                        fields.append(self.allocator, ast.Field{
                            .name = field_name.lexeme,
                            .type_annotation = field_type,
                        }) catch |err| {
                            ast.deinitType(&field_type, self.allocator);
                            return err;
                        };

                        if (!self.match(.comma)) break;
                    }
                }
                _ = try self.consume(.rbrace, "expected '}' after variant fields");
            }

            const fields_slice = fields.toOwnedSlice(self.allocator) catch |err| {
                return err;
            };

            variants.append(self.allocator, ast.DomainVariant{
                .name = variant_name.lexeme,
                .fields = fields_slice,
            }) catch |err| {
                for (fields_slice) |field| {
                    ast.deinitType(&field.type_annotation, self.allocator);
                }
                self.allocator.free(fields_slice);
                return err;
            };
        }

        _ = try self.consume(.rbrace, "expected '}' after domain variants");

        return ast.Stmt{
            .domain_decl = ast.DomainDecl{
                .name = name.lexeme,
                .error_union = null,
                .variants = try variants.toOwnedSlice(self.allocator),
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn statement(self: *Parser) ParseError!ast.Stmt {
        if (self.match(.const_kw)) return try self.constDeclaration();
        if (self.match(.var_kw)) return try self.varDeclaration();
        if (self.match(.return_kw)) return try self.returnStatement();
        if (self.match(.defer_kw)) return try self.deferStatement();
        if (self.match(.if_kw)) return try self.ifStatement();
        if (self.match(.while_kw)) return try self.whileStatement();
        if (self.match(.for_kw)) return try self.forStatement();
        if (self.match(.match_kw)) return try self.matchStatement();
        if (self.match(.break_kw)) {
            _ = try self.consume(.semicolon, "expected ';' after 'break'");
            return ast.Stmt{ .break_stmt = {} };
        }
        if (self.match(.continue_kw)) {
            _ = try self.consume(.semicolon, "expected ';' after 'continue'");
            return ast.Stmt{ .continue_stmt = {} };
        }

        return try self.expressionStatement();
    }

    fn constDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected constant name");

        var type_annotation: ?ast.Type = null;
        if (self.match(.colon)) {
            type_annotation = try self.parseType();
        }
        errdefer {
            if (type_annotation) |ta| {
                ast.deinitType(&ta, self.allocator);
            }
        }

        _ = try self.consume(.eq, "expected '=' after constant name");
        const value = try self.expression();
        _ = try self.consume(.semicolon, "expected ';' after constant declaration");

        return ast.Stmt{
            .const_decl = ast.ConstDecl{
                .name = name.lexeme,
                .type_annotation = type_annotation,
                .value = value,
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn varDeclaration(self: *Parser) ParseError!ast.Stmt {
        const name = try self.consume(.identifier, "expected variable name");

        var type_annotation: ?ast.Type = null;
        if (self.match(.colon)) {
            type_annotation = try self.parseType();
        }
        errdefer {
            if (type_annotation) |ta| {
                ast.deinitType(&ta, self.allocator);
            }
        }

        _ = try self.consume(.eq, "expected '=' after variable name");
        const value = try self.expression();
        _ = try self.consume(.semicolon, "expected ';' after variable declaration");

        return ast.Stmt{
            .var_decl = ast.VarDecl{
                .name = name.lexeme,
                .type_annotation = type_annotation,
                .value = value,
                .name_loc = .{ .line = name.line, .column = name.column },
            },
        };
    }

    fn returnStatement(self: *Parser) ParseError!ast.Stmt {
        const return_token = self.previous();
        var value: ?*ast.Expr = null;

        if (!self.check(.semicolon)) {
            value = try self.expression();
        }

        _ = try self.consume(.semicolon, "expected ';' after return statement");

        return ast.Stmt{ .return_stmt = .{
            .value = value,
            .loc = .{ .line = return_token.line, .column = return_token.column },
        } };
    }

    fn deferStatement(self: *Parser) ParseError!ast.Stmt {
        const expr = try self.expression();
        _ = try self.consume(.semicolon, "expected ';' after defer statement");

        return ast.Stmt{ .defer_stmt = expr };
    }

    fn ifStatement(self: *Parser) ParseError!ast.Stmt {
        const condition = try self.expression();
        errdefer ast.deinitExpr(condition, self.allocator);

        _ = try self.consume(.lbrace, "expected '{' after if condition");
        const then_block = try self.block();
        errdefer {
            for (then_block) |*stmt| {
                ast.deinitStmt(stmt, self.allocator);
            }
            self.allocator.free(then_block);
        }

        var else_block: ?[]ast.Stmt = null;
        if (self.match(.else_kw)) {
            if (self.check(.if_kw)) {
                const nested_if = try self.statement();
                const else_stmts = try self.allocator.alloc(ast.Stmt, 1);
                else_stmts[0] = nested_if;
                else_block = else_stmts;
            } else {
                _ = try self.consume(.lbrace, "expected '{' or 'if' after 'else'");
                else_block = try self.block();
            }
        }

        return ast.Stmt{
            .if_stmt = ast.IfStmt{
                .condition = condition,
                .then_block = then_block,
                .else_block = else_block,
            },
        };
    }

    fn whileStatement(self: *Parser) ParseError!ast.Stmt {
        const condition = try self.expression();
        errdefer ast.deinitExpr(condition, self.allocator);

        _ = try self.consume(.lbrace, "expected '{' after while condition");
        const body = try self.block();

        return ast.Stmt{
            .while_stmt = ast.WhileStmt{
                .condition = condition,
                .body = body,
            },
        };
    }

    fn forStatement(self: *Parser) ParseError!ast.Stmt {
        const iterator = try self.consume(.identifier, "expected iterator name");
        _ = try self.consume(.in_kw, "expected 'in' after iterator");
        const iterable = try self.expression();
        errdefer ast.deinitExpr(iterable, self.allocator);

        _ = try self.consume(.lbrace, "expected '{' after for expression");
        const body = try self.block();

        return ast.Stmt{
            .for_stmt = ast.ForStmt{
                .iterator = iterator.lexeme,
                .iterator_loc = .{ .line = iterator.line, .column = iterator.column },
                .iterable = iterable,
                .body = body,
            },
        };
    }

    fn matchStatement(self: *Parser) ParseError!ast.Stmt {
        const value = try self.expression();
        errdefer ast.deinitExpr(value, self.allocator);

        _ = try self.consume(.lbrace, "expected '{' after match value");

        var arms: std.ArrayList(ast.MatchArm) = .empty;
        errdefer {
            for (arms.items) |*arm| {
                ast.deinitExpr(arm.body, self.allocator);
            }
            arms.deinit(self.allocator);
        }

        while (!self.check(.rbrace) and !self.isAtEnd()) {
            const pattern = try self.parsePattern();
            _ = try self.consume(.arrow, "expected '->' after pattern");
            const body = try self.expression();
            arms.append(self.allocator, ast.MatchArm{
                .pattern = pattern,
                .body = body,
            }) catch |err| {
                ast.deinitExpr(body, self.allocator);
                return err;
            };
            _ = try self.consume(.semicolon, "expected ';' after match arm");
        }

        _ = try self.consume(.rbrace, "expected '}' after match arms");

        return ast.Stmt{
            .match_stmt = ast.MatchStmt{
                .value = value,
                .arms = try arms.toOwnedSlice(self.allocator),
            },
        };
    }

    fn expressionStatement(self: *Parser) ParseError!ast.Stmt {
        const expr = try self.expression();
        errdefer ast.deinitExpr(expr, self.allocator);

        // check for assignment
        if (self.match(.eq)) {
            // expr should be an identifier
            const target = switch (expr.*) {
                .identifier => |id| id,
                else => {
                    ast.deinitExpr(expr, self.allocator);
                    self.allocator.destroy(expr);
                    return ParseError.InvalidSyntax;
                },
            };

            const value = self.expression() catch |err| {
                self.allocator.destroy(expr);
                return err;
            };
            _ = self.consume(.semicolon, "expected ';' after assignment") catch |err| {
                ast.deinitExpr(value, self.allocator);
                self.allocator.destroy(expr);
                return err;
            };

            self.allocator.destroy(expr);

            return ast.Stmt{ .assign_stmt = ast.AssignStmt{
                .target = target,
                .value = value,
            } };
        }

        _ = try self.consume(.semicolon, "expected ';' after expression");

        return ast.Stmt{ .expr_stmt = expr };
    }

    fn block(self: *Parser) ParseError![]ast.Stmt {
        var statements: std.ArrayList(ast.Stmt) = .empty;
        errdefer {
            for (statements.items) |*stmt| {
                ast.deinitStmt(stmt, self.allocator);
            }
            statements.deinit(self.allocator);
        }

        while (!self.check(.rbrace) and !self.isAtEnd()) {
            const decl = try self.declaration();
            statements.append(self.allocator, decl) catch |err| {
                ast.deinitStmt(&decl, self.allocator);
                return err;
            };
        }

        _ = try self.consume(.rbrace, "expected '}' after block");

        return try statements.toOwnedSlice(self.allocator);
    }

    fn expression(self: *Parser) ParseError!*ast.Expr {
        return try self.rangeExpr();
    }

    fn rangeExpr(self: *Parser) ParseError!*ast.Expr {
        const expr = try self.logicalOr();

        if (self.match(.dotdot)) {
            const end = self.logicalOr() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const range_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(end, self.allocator);
                return err;
            };
            range_expr.* = ast.Expr{
                .range = ast.RangeExpr{
                    .start = expr,
                    .end = end,
                    .inclusive = false,
                },
            };
            return range_expr;
        }

        return expr;
    }

    fn logicalOr(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.logicalAnd();

        while (self.match(.pipe_pipe)) {
            const right = self.logicalAnd() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = .logical_or,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn logicalAnd(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.equality();

        while (self.match(.ampersand_ampersand)) {
            const right = self.equality() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = .logical_and,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn equality(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.comparison();

        while (true) {
            const op: ?ast.BinaryOp = if (self.match(.eq_eq))
                .eq
            else if (self.match(.bang_eq))
                .ne
            else
                null;

            if (op == null) break;

            const right = self.comparison() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = op.?,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn comparison(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.bitwiseOr();

        while (true) {
            const op: ?ast.BinaryOp = if (self.match(.lt))
                .lt
            else if (self.match(.gt))
                .gt
            else if (self.match(.lt_eq))
                .le
            else if (self.match(.gt_eq))
                .ge
            else
                null;

            if (op == null) break;

            const right = self.bitwiseOr() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = op.?,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn bitwiseOr(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.bitwiseXor();

        while (self.match(.pipe)) {
            const right = self.bitwiseXor() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = .bitwise_or,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn bitwiseXor(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.bitwiseAnd();

        while (self.match(.caret)) {
            const right = self.bitwiseAnd() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = .bitwise_xor,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn bitwiseAnd(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.shift();

        while (self.match(.ampersand)) {
            const right = self.shift() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = .bitwise_and,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn shift(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.term();

        while (true) {
            const op: ?ast.BinaryOp = if (self.match(.lt_lt))
                .shift_left
            else if (self.match(.gt_gt))
                .shift_right
            else
                null;

            if (op == null) break;

            const right = self.term() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = op.?,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn term(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.factor();

        while (true) {
            const op: ?ast.BinaryOp = if (self.match(.plus))
                .add
            else if (self.match(.plus_plus))
                .concat
            else if (self.match(.minus))
                .subtract
            else
                null;

            if (op == null) break;

            const right = self.factor() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = op.?,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn factor(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.unary();

        while (true) {
            const op: ?ast.BinaryOp = if (self.match(.star))
                .multiply
            else if (self.match(.slash))
                .divide
            else if (self.match(.percent))
                .modulo
            else
                null;

            if (op == null) break;

            const right = self.unary() catch |err| {
                ast.deinitExpr(expr, self.allocator);
                return err;
            };
            const binary_expr = self.allocator.create(ast.Expr) catch |err| {
                ast.deinitExpr(expr, self.allocator);
                ast.deinitExpr(right, self.allocator);
                return err;
            };
            binary_expr.* = ast.Expr{
                .binary = ast.BinaryExpr{
                    .left = expr,
                    .op = op.?,
                    .right = right,
                },
            };
            expr = binary_expr;
        }

        return expr;
    }

    fn unary(self: *Parser) ParseError!*ast.Expr {
        if (self.match(.minus)) {
            const operand = try self.unary();
            const unary_expr = try self.allocator.create(ast.Expr);
            unary_expr.* = ast.Expr{
                .unary = ast.UnaryExpr{
                    .op = .negate,
                    .operand = operand,
                },
            };
            return unary_expr;
        }

        if (self.match(.bang)) {
            const operand = try self.unary();
            const unary_expr = try self.allocator.create(ast.Expr);
            unary_expr.* = ast.Expr{
                .unary = ast.UnaryExpr{
                    .op = .not,
                    .operand = operand,
                },
            };
            return unary_expr;
        }

        if (self.match(.tilde)) {
            const operand = try self.unary();
            const unary_expr = try self.allocator.create(ast.Expr);
            unary_expr.* = ast.Expr{
                .unary = ast.UnaryExpr{
                    .op = .bitwise_not,
                    .operand = operand,
                },
            };
            return unary_expr;
        }

        if (self.match(.ok_kw)) {
            const value = try self.unary();
            const ok_expr = try self.allocator.create(ast.Expr);
            ok_expr.* = ast.Expr{ .ok = value };
            return ok_expr;
        }

        if (self.match(.err_kw)) {
            const variant = try self.consume(.identifier, "expected error variant name");
            _ = try self.consume(.lbrace, "expected '{' after error variant name");

            var fields: std.ArrayList(ast.FieldAssignment) = .empty;
            errdefer {
                for (fields.items) |field| {
                    ast.deinitExpr(field.value, self.allocator);
                }
                fields.deinit(self.allocator);
            }

            if (!self.check(.rbrace)) {
                while (true) {
                    const field_name = try self.consume(.identifier, "expected field name");
                    _ = try self.consume(.colon, "expected ':' after field name");
                    const field_value = try self.expression();

                    try fields.append(self.allocator, ast.FieldAssignment{
                        .name = field_name.lexeme,
                        .value = field_value,
                    });

                    if (!self.match(.comma)) break;
                }
            }

            _ = try self.consume(.rbrace, "expected '}' after error fields");

            const err_expr = try self.allocator.create(ast.Expr);
            err_expr.* = ast.Expr{
                .err = ast.ErrorExpr{
                    .variant = variant.lexeme,
                    .fields = try fields.toOwnedSlice(self.allocator),
                },
            };
            return err_expr;
        }

        if (self.match(.check_kw)) {
            const value = try self.unary();

            var context_frame: ?[]ast.FieldAssignment = null;
            if (self.match(.with_kw)) {
                _ = try self.consume(.lbrace, "expected '{' after 'with'");

                var frame_fields: std.ArrayList(ast.FieldAssignment) = .empty;
                errdefer {
                    for (frame_fields.items) |field| {
                        ast.deinitExpr(field.value, self.allocator);
                    }
                    frame_fields.deinit(self.allocator);
                }

                if (!self.check(.rbrace)) {
                    while (true) {
                        const field_name = try self.consume(.identifier, "expected field name");
                        _ = try self.consume(.colon, "expected ':' after field name");
                        const field_value = try self.expression();

                        try frame_fields.append(self.allocator, ast.FieldAssignment{
                            .name = field_name.lexeme,
                            .value = field_value,
                        });

                        if (!self.match(.comma)) break;
                    }
                }

                _ = try self.consume(.rbrace, "expected '}' after context frame");
                context_frame = try frame_fields.toOwnedSlice(self.allocator);
            }

            const check_expr = try self.allocator.create(ast.Expr);
            check_expr.* = ast.Expr{
                .check = ast.CheckExpr{
                    .expr = value,
                    .context_frame = context_frame,
                },
            };
            return check_expr;
        }

        if (self.match(.map_error_kw)) {
            const value = try self.unary();
            _ = try self.consume(.using_kw, "expected 'using' after map_error expression");
            _ = try self.consume(.lparen, "expected '(' after 'using'");
            const param_name = try self.consume(.identifier, "expected parameter name");
            _ = try self.consume(.fat_arrow, "expected '=>' after parameter");
            const transform = try self.expression();
            _ = try self.consume(.rparen, "expected ')' after transform expression");

            const map_error_expr = try self.allocator.create(ast.Expr);
            map_error_expr.* = ast.Expr{
                .map_error = ast.MapErrorExpr{
                    .expr = value,
                    .param_name = param_name.lexeme,
                    .transform = transform,
                },
            };
            return map_error_expr;
        }

        if (self.match(.unsafe_cast_kw)) {
            _ = try self.consume(.lt, "expected '<' after unsafe_cast");
            const target_type = try self.parseType();
            _ = try self.consume(.gt, "expected '>' after type");
            _ = try self.consume(.lparen, "expected '(' after type");
            const value = try self.expression();
            _ = try self.consume(.rparen, "expected ')' after expression");

            const cast_expr = try self.allocator.create(ast.Expr);
            cast_expr.* = ast.Expr{
                .unsafe_cast = ast.UnsafeCastExpr{
                    .target_type = target_type,
                    .expr = value,
                },
            };
            return cast_expr;
        }

        if (self.match(.comptime_kw)) {
            const value = try self.unary();
            const comptime_expr = try self.allocator.create(ast.Expr);
            comptime_expr.* = ast.Expr{ .comptime_expr = value };
            return comptime_expr;
        }

        return try self.postfix();
    }

    fn postfix(self: *Parser) ParseError!*ast.Expr {
        var expr = try self.primary();

        while (true) {
            if (self.match(.lbracket)) {
                // Index access
                const index = self.expression() catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };
                _ = self.consume(.rbracket, "expected ']' after index") catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    ast.deinitExpr(index, self.allocator);
                    return err;
                };

                const index_expr = self.allocator.create(ast.Expr) catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    ast.deinitExpr(index, self.allocator);
                    return err;
                };
                index_expr.* = ast.Expr{
                    .index_access = ast.IndexAccessExpr{
                        .object = expr,
                        .index = index,
                    },
                };
                expr = index_expr;
            } else if (self.match(.lparen)) {
                var args: std.ArrayList(*ast.Expr) = .empty;
                errdefer {
                    for (args.items) |arg| {
                        ast.deinitExpr(arg, self.allocator);
                    }
                    args.deinit(self.allocator);
                }

                if (!self.check(.rparen)) {
                    while (true) {
                        const arg = self.expression() catch |err| {
                            ast.deinitExpr(expr, self.allocator);
                            return err;
                        };
                        args.append(self.allocator, arg) catch |err| {
                            ast.deinitExpr(arg, self.allocator);
                            ast.deinitExpr(expr, self.allocator);
                            return err;
                        };
                        if (!self.match(.comma)) break;
                    }
                }

                _ = self.consume(.rparen, "expected ')' after arguments") catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };

                const call_expr = self.allocator.create(ast.Expr) catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };

                const args_slice = args.toOwnedSlice(self.allocator) catch |err| {
                    self.allocator.destroy(call_expr);
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };

                call_expr.* = ast.Expr{
                    .call = ast.CallExpr{
                        .callee = expr,
                        .args = args_slice,
                    },
                };
                expr = call_expr;
            } else if (self.match(.dot)) {
                const field = self.consume(.identifier, "expected field name after '.'") catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };
                const field_expr = self.allocator.create(ast.Expr) catch |err| {
                    ast.deinitExpr(expr, self.allocator);
                    return err;
                };
                field_expr.* = ast.Expr{
                    .field_access = ast.FieldAccessExpr{
                        .object = expr,
                        .field = field.lexeme,
                    },
                };
                expr = field_expr;
            } else {
                break;
            }
        }

        return expr;
    }

    fn primary(self: *Parser) ParseError!*ast.Expr {
        if (self.match(.true_kw)) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .bool_literal = true };
            return expr;
        }

        if (self.match(.false_kw)) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .bool_literal = false };
            return expr;
        }

        if (self.match(.null_kw)) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .null_literal = {} };
            return expr;
        }

        if (self.match(.unit_kw)) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .unit_literal = {} };
            return expr;
        }

        if (self.match(.number)) {
            const token = self.previous();
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .number = token.lexeme };
            return expr;
        }

        if (self.match(.string)) {
            const token = self.previous();
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .string = token.lexeme };
            return expr;
        }

        if (self.match(.bytes)) {
            const token = self.previous();
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .bytes = token.lexeme };
            return expr;
        }

        if (self.match(.char)) {
            const token = self.previous();
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .char = token.lexeme };
            return expr;
        }

        if (self.match(.identifier)) {
            const token = self.previous();
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .identifier = .{
                .name = token.lexeme,
                .loc = .{ .line = token.line, .column = token.column },
            } };
            return expr;
        }

        // Array literal [a, b, c]
        if (self.match(.lbracket)) {
            var elements: std.ArrayList(*ast.Expr) = .empty;
            errdefer {
                for (elements.items) |elem| {
                    ast.deinitExpr(elem, self.allocator);
                }
                elements.deinit(self.allocator);
            }

            if (!self.check(.rbracket)) {
                const first_elem = try self.expression();
                elements.append(self.allocator, first_elem) catch |err| {
                    ast.deinitExpr(first_elem, self.allocator);
                    return err;
                };

                while (self.match(.comma)) {
                    if (self.check(.rbracket)) break;
                    const elem = try self.expression();
                    elements.append(self.allocator, elem) catch |err| {
                        ast.deinitExpr(elem, self.allocator);
                        return err;
                    };
                }
            }

            _ = try self.consume(.rbracket, "expected ']' after array elements");

            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .array_literal = .{ .elements = elements.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory } };
            return expr;
        }

        // Record literal { field: value, ... }
        if (self.match(.lbrace)) {
            var fields: std.ArrayList(ast.FieldAssignment) = .empty;
            errdefer {
                for (fields.items) |field| {
                    ast.deinitExpr(field.value, self.allocator);
                }
                fields.deinit(self.allocator);
            }

            if (!self.check(.rbrace)) {
                while (true) {
                    const field_name = try self.consume(.identifier, "expected field name");
                    _ = try self.consume(.colon, "expected ':' after field name");
                    const field_value = try self.expression();

                    try fields.append(self.allocator, ast.FieldAssignment{
                        .name = field_name.lexeme,
                        .value = field_value,
                    });

                    if (!self.match(.comma)) break;
                }
            }

            _ = try self.consume(.rbrace, "expected '}' after record fields");

            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .record_literal = .{ .fields = try fields.toOwnedSlice(self.allocator) } };
            return expr;
        }

        // Anonymous function: function(params) -> ReturnType { body }
        if (self.match(.function_kw)) {
            _ = try self.consume(.lparen, "expected '(' after 'function'");

            var params: std.ArrayList(ast.Param) = .empty;
            errdefer {
                for (params.items) |*param| {
                    ast.deinitType(&param.type_annotation, self.allocator);
                }
                params.deinit(self.allocator);
            }

            if (!self.check(.rparen)) {
                while (true) {
                    var is_capability = false;
                    var is_inout = false;

                    if (self.match(.cap_kw)) {
                        is_capability = true;
                    }

                    if (self.match(.inout_kw)) {
                        is_inout = true;
                    }

                    const param_name = try self.consume(.identifier, "expected parameter name");
                    _ = try self.consume(.colon, "expected ':' after parameter name");
                    const param_type = try self.parseType();

                    params.append(self.allocator, ast.Param{
                        .name = param_name.lexeme,
                        .type_annotation = param_type,
                        .is_inout = is_inout,
                        .is_capability = is_capability,
                        .name_loc = .{ .line = param_name.line, .column = param_name.column },
                    }) catch |err| {
                        ast.deinitType(&param_type, self.allocator);
                        return err;
                    };

                    if (!self.match(.comma)) break;
                }
            }

            _ = try self.consume(.rparen, "expected ')' after parameters");
            _ = try self.consume(.arrow, "expected '->' after parameters");

            const return_type = try self.parseType();

            var error_domain: ?[]const u8 = null;
            if (self.match(.error_kw)) {
                const err_token = try self.consume(.identifier, "expected error domain name");
                error_domain = err_token.lexeme;
            }

            var effects: std.ArrayList([]const u8) = .empty;
            errdefer effects.deinit(self.allocator);

            if (self.match(.effects_kw)) {
                _ = try self.consume(.lbracket, "expected '[' after 'effects'");
                if (!self.check(.rbracket)) {
                    while (true) {
                        const effect = try self.consume(.identifier, "expected effect name");
                        try effects.append(self.allocator, effect.lexeme);
                        if (!self.match(.comma)) break;
                    }
                }
                _ = try self.consume(.rbracket, "expected ']' after effects");
            }

            _ = try self.consume(.lbrace, "expected '{' before function body");
            const body = try self.block();

            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{
                .anonymous_function = ast.AnonymousFunctionExpr{
                    .params = try params.toOwnedSlice(self.allocator),
                    .return_type = return_type,
                    .error_domain = error_domain,
                    .effects = try effects.toOwnedSlice(self.allocator),
                    .body = body,
                },
            };
            return expr;
        }

        // Context block: with context { ... } in { ... }
        if (self.match(.with_kw)) {
            if (self.match(.context_kw)) {
                _ = try self.consume(.lbrace, "expected '{' after 'context'");

                var context_items: std.ArrayList(ast.FieldAssignment) = .empty;
                errdefer {
                    for (context_items.items) |item| {
                        ast.deinitExpr(item.value, self.allocator);
                    }
                    context_items.deinit(self.allocator);
                }

                if (!self.check(.rbrace)) {
                    while (true) {
                        const item_name = try self.consume(.identifier, "expected context item name");
                        _ = try self.consume(.colon, "expected ':' after context item name");
                        const item_value = try self.expression();

                        try context_items.append(self.allocator, ast.FieldAssignment{
                            .name = item_name.lexeme,
                            .value = item_value,
                        });

                        if (!self.match(.comma)) break;
                    }
                }

                _ = try self.consume(.rbrace, "expected '}' after context items");
                _ = try self.consume(.in_kw, "expected 'in' after context block");
                _ = try self.consume(.lbrace, "expected '{' after 'in'");
                const body = try self.block();

                const expr = try self.allocator.create(ast.Expr);
                expr.* = ast.Expr{
                    .context_block = ast.ContextBlockExpr{
                        .context_items = try context_items.toOwnedSlice(self.allocator),
                        .body = body,
                    },
                };
                return expr;
            }
        }

        // Parenthesized expression
        if (self.match(.lparen)) {
            const expr = try self.expression();
            _ = try self.consume(.rparen, "expected ')' after expression");
            return expr;
        }

        return ParseError.UnexpectedToken;
    }

    fn parseType(self: *Parser) ParseError!ast.Type {
        if (self.match(.number)) {
            const num = self.previous();
            const loc = ast.Location{ .line = num.line, .column = num.column };
            return ast.Type{ .simple = .{ .name = num.lexeme, .loc = loc } };
        }

        if (self.match(.identifier)) {
            const name = self.previous();
            const loc = ast.Location{ .line = name.line, .column = name.column };

            // check for generic type parameters
            if (self.match(.lt)) {
                var type_args: std.ArrayList(ast.Type) = .empty;
                errdefer {
                    for (type_args.items) |*arg| {
                        ast.deinitType(arg, self.allocator);
                    }
                    type_args.deinit(self.allocator);
                }

                // parse first type argument
                const first_arg = try self.parseType();
                type_args.append(self.allocator, first_arg) catch |err| {
                    ast.deinitType(&first_arg, self.allocator);
                    return err;
                };

                // parse additional type arguments
                while (self.match(.comma)) {
                    const arg = try self.parseType();
                    type_args.append(self.allocator, arg) catch |err| {
                        ast.deinitType(&arg, self.allocator);
                        return err;
                    };
                }

                _ = try self.consume(.gt, "expected '>' after generic type arguments");

                return ast.Type{ .generic = .{
                    .name = name.lexeme,
                    .type_args = try type_args.toOwnedSlice(self.allocator),
                    .loc = loc,
                } };
            }

            return ast.Type{ .simple = .{ .name = name.lexeme, .loc = loc } };
        }

        // record type: { field: Type, field2: Type }
        if (self.match(.lbrace)) {
            const loc = ast.Location{ .line = self.previous().line, .column = self.previous().column };
            var fields: std.ArrayList(ast.RecordTypeField) = .empty;
            errdefer {
                for (fields.items) |*f| {
                    ast.deinitType(&f.type_annotation, self.allocator);
                }
                fields.deinit(self.allocator);
            }

            if (!self.check(.rbrace)) {
                while (true) {
                    const field_name = try self.consume(.identifier, "expected field name");
                    _ = try self.consume(.colon, "expected ':' after field name");
                    const field_type = try self.parseType();

                    fields.append(self.allocator, ast.RecordTypeField{
                        .name = field_name.lexeme,
                        .type_annotation = field_type,
                    }) catch |err| {
                        ast.deinitType(&field_type, self.allocator);
                        return err;
                    };

                    if (!self.match(.comma)) break;
                }
            }

            _ = try self.consume(.rbrace, "expected '}' after record type fields");

            return ast.Type{ .record_type = .{
                .fields = try fields.toOwnedSlice(self.allocator),
                .loc = loc,
            } };
        }

        // union type: | Variant1 | Variant2 { field: Type }
        if (self.match(.pipe)) {
            const loc = ast.Location{ .line = self.previous().line, .column = self.previous().column };
            var variants: std.ArrayList(ast.UnionVariant) = .empty;
            errdefer {
                for (variants.items) |variant| {
                    if (variant.fields) |vfields| {
                        for (vfields) |*f| {
                            ast.deinitType(&f.type_annotation, self.allocator);
                        }
                        self.allocator.free(vfields);
                    }
                }
                variants.deinit(self.allocator);
            }

            while (true) {
                const variant_name = try self.consume(.identifier, "expected variant name");

                var variant_fields: ?[]ast.RecordTypeField = null;
                if (self.match(.lbrace)) {
                    var vfields: std.ArrayList(ast.RecordTypeField) = .empty;
                    errdefer {
                        for (vfields.items) |*f| {
                            ast.deinitType(&f.type_annotation, self.allocator);
                        }
                        vfields.deinit(self.allocator);
                    }

                    if (!self.check(.rbrace)) {
                        while (true) {
                            const field_name = try self.consume(.identifier, "expected field name");
                            _ = try self.consume(.colon, "expected ':' after field name");
                            const field_type = try self.parseType();

                            vfields.append(self.allocator, ast.RecordTypeField{
                                .name = field_name.lexeme,
                                .type_annotation = field_type,
                            }) catch |err| {
                                ast.deinitType(&field_type, self.allocator);
                                return err;
                            };

                            if (!self.match(.comma)) break;
                        }
                    }

                    _ = try self.consume(.rbrace, "expected '}' after variant fields");
                    variant_fields = try vfields.toOwnedSlice(self.allocator);
                }

                try variants.append(self.allocator, ast.UnionVariant{
                    .name = variant_name.lexeme,
                    .fields = variant_fields,
                });

                if (!self.match(.pipe)) break;
            }

            return ast.Type{ .union_type = .{
                .variants = try variants.toOwnedSlice(self.allocator),
                .loc = loc,
            } };
        }

        return ParseError.InvalidSyntax;
    }

    fn parsePattern(self: *Parser) ParseError!ast.Pattern {
        if (self.match(.identifier)) {
            const token = self.previous();
            if (std.mem.eql(u8, token.lexeme, "_")) {
                return ast.Pattern{ .wildcard = {} };
            }
            return ast.Pattern{ .identifier = token.lexeme };
        }

        if (self.match(.number)) {
            const token = self.previous();
            return ast.Pattern{ .number = token.lexeme };
        }

        if (self.match(.string)) {
            const token = self.previous();
            return ast.Pattern{ .string = token.lexeme };
        }

        return ParseError.InvalidSyntax;
    }

    fn check(self: *const Parser, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn match(self: *Parser, token_type: TokenType) bool {
        if (!self.check(token_type)) return false;
        _ = self.advance();
        return true;
    }

    fn advance(self: *Parser) Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.previous();
    }

    fn isAtEnd(self: *const Parser) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *const Parser) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *const Parser) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ParseError!Token {
        if (self.check(token_type)) return self.advance();

        std.debug.print("Parse error at line {d}: {s}\n", .{ self.peek().line, message });
        std.debug.print("Got token: {s} (type: {any})\n", .{ self.peek().lexeme, self.peek().type });

        return ParseError.UnexpectedToken;
    }

    // consumes an identifier or any keyword token and returns it
    // this allows keywords to be used as names in certain contexts (e.g., package names)
    fn consumeIdentifierOrKeyword(self: *Parser, message: []const u8) ParseError!Token {
        const token = self.peek();
        if (token.type == .identifier or self.isKeyword(token.type)) {
            return self.advance();
        }

        std.debug.print("Parse error at line {d}: {s}\n", .{ token.line, message });
        std.debug.print("Got token: {s} (type: {any})\n", .{ token.lexeme, token.type });

        return ParseError.UnexpectedToken;
    }

    fn isKeyword(self: *const Parser, token_type: TokenType) bool {
        _ = self;
        return switch (token_type) {
            .const_kw, .var_kw, .function_kw, .return_kw, .defer_kw, .inout_kw, .import_kw, .export_kw, .pub_kw, .package_kw, .type_kw, .domain_kw, .effects_kw, .capability_kw, .with_kw, .context_kw, .match_kw, .if_kw, .else_kw, .for_kw, .while_kw, .break_kw, .continue_kw, .comptime_kw, .derivation_kw, .use_kw, .error_kw, .as_kw, .where_kw, .asm_kw, .component_kw, .in_kw, .out_kw, .using_kw, .ok_kw, .err_kw, .check_kw, .ensure_kw, .map_error_kw, .cap_kw, .unsafe_cast_kw, .unknown_kw, .unit_kw, .distribute_kw, .infer_kw, .map_kw, .true_kw, .false_kw, .null_kw => true,
            else => false,
        };
    }
};
