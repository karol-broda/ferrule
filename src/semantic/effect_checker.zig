const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const typed_ast = @import("../typed_ast.zig");
const context = @import("../context.zig");

pub const EffectChecker = struct {
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,

    // compilation context for arena-based memory management
    compilation_context: *context.CompilationContext,

    pub fn init(
        ctx: *context.CompilationContext,
        symbols: *symbol_table.SymbolTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) EffectChecker {
        return .{
            .symbols = symbols,
            .diagnostics_list = diagnostics_list,
            .allocator = ctx.permanentAllocator(),
            .source_file = source_file,
            .compilation_context = ctx,
        };
    }

    pub fn checkModule(self: *EffectChecker, module: ast.Module) !void {
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.checkFunction(stmt.function_decl);
            }
        }
    }

    pub fn checkFunction(self: *EffectChecker, func: ast.FunctionDecl) std.mem.Allocator.Error!void {
        if (self.symbols.lookupGlobal(func.name)) |symbol| {
            if (symbol != .function) return;

            const func_symbol = symbol.function;
            var collected_effects = std.ArrayList(types.Effect){};
            collected_effects.clearRetainingCapacity();
            defer collected_effects.deinit(self.allocator);

            for (func.body) |stmt| {
                try self.collectEffectsFromStmt(stmt, &collected_effects);
            }

            for (collected_effects.items) |effect| {
                var found = false;
                for (func_symbol.effects) |declared_effect| {
                    if (effect == declared_effect) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "function '{s}' uses effect '{any}' but doesn't declare it",
                            .{ func.name, effect },
                        ),
                        .{
                            .file = self.source_file,
                            .line = func.name_loc.line,
                            .column = func.name_loc.column,
                            .length = func.name.len,
                        },
                        try self.allocator.dupe(u8, "add the effect to the function signature"),
                    );
                }
            }

            const is_main = std.mem.eql(u8, func.name, "main");

            for (func_symbol.effects) |declared_effect| {
                const has_capability = blk: {
                    if (is_main and self.isAmbientCapability(declared_effect)) {
                        break :blk true;
                    }
                    for (func.params, func_symbol.is_capability_param) |param, is_cap| {
                        if (is_cap and self.isCapabilityForEffect(param.type_annotation, declared_effect)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                if (!has_capability and self.requiresCapability(declared_effect)) {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "function '{s}' declares effect '{any}' but has no corresponding capability parameter",
                            .{ func.name, declared_effect },
                        ),
                        .{
                            .file = self.source_file,
                            .line = func.name_loc.line,
                            .column = func.name_loc.column,
                            .length = func.name.len,
                        },
                        try std.fmt.allocPrint(
                            self.allocator,
                            "add a capability parameter like 'cap {s}: {s}'",
                            .{ @tagName(declared_effect), self.getCapabilityTypeName(declared_effect) },
                        ),
                    );
                }
            }
        }
    }

    fn collectEffectsFromStmt(self: *EffectChecker, stmt: ast.Stmt, effects: *std.ArrayList(types.Effect)) std.mem.Allocator.Error!void {
        switch (stmt) {
            .expr_stmt => |expr| try self.collectEffectsFromExpr(expr, effects),
            .if_stmt => |is| {
                try self.collectEffectsFromExpr(is.condition, effects);
                for (is.then_block) |then_stmt| {
                    try self.collectEffectsFromStmt(then_stmt, effects);
                }
                if (is.else_block) |else_block| {
                    for (else_block) |else_stmt| {
                        try self.collectEffectsFromStmt(else_stmt, effects);
                    }
                }
            },
            .while_stmt => |ws| {
                try self.collectEffectsFromExpr(ws.condition, effects);
                for (ws.body) |body_stmt| {
                    try self.collectEffectsFromStmt(body_stmt, effects);
                }
            },
            .for_stmt => |fs| {
                try self.collectEffectsFromExpr(fs.iterable, effects);
                for (fs.body) |body_stmt| {
                    try self.collectEffectsFromStmt(body_stmt, effects);
                }
            },
            .match_stmt => |ms| {
                try self.collectEffectsFromExpr(ms.value, effects);
                for (ms.arms) |arm| {
                    try self.collectEffectsFromExpr(arm.body, effects);
                }
            },
            .return_stmt => |return_stmt| {
                if (return_stmt.value) |expr| {
                    try self.collectEffectsFromExpr(expr, effects);
                }
            },
            .assign_stmt => |as| {
                try self.collectEffectsFromExpr(as.value, effects);
            },
            .var_decl => |vd| {
                try self.collectEffectsFromExpr(vd.value, effects);
            },
            .const_decl => |cd| {
                try self.collectEffectsFromExpr(cd.value, effects);
            },
            else => {},
        }
    }

    fn collectEffectsFromExpr(self: *EffectChecker, expr: *ast.Expr, effects: *std.ArrayList(types.Effect)) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .call => |ce| {
                if (ce.callee.* == .identifier) {
                    const func_name = ce.callee.identifier.name;
                    if (self.symbols.lookupGlobal(func_name)) |symbol| {
                        if (symbol == .function) {
                            const func = symbol.function;
                            for (func.effects) |effect| {
                                var already_added = false;
                                for (effects.items) |existing| {
                                    if (existing == effect) {
                                        already_added = true;
                                        break;
                                    }
                                }
                                if (!already_added) {
                                    try effects.append(self.allocator, effect);
                                }
                            }
                        }
                    }
                }

                try self.collectEffectsFromExpr(ce.callee, effects);
                for (ce.args) |arg| {
                    try self.collectEffectsFromExpr(arg, effects);
                }
            },
            .binary => |be| {
                try self.collectEffectsFromExpr(be.left, effects);
                try self.collectEffectsFromExpr(be.right, effects);
            },
            .unary => |ue| {
                try self.collectEffectsFromExpr(ue.operand, effects);
            },
            .field_access => |fa| {
                try self.collectEffectsFromExpr(fa.object, effects);
            },
            .ok => |ok_expr| {
                try self.collectEffectsFromExpr(ok_expr, effects);
            },
            .check => |ce| {
                try self.collectEffectsFromExpr(ce.expr, effects);
            },
            .ensure => |ee| {
                try self.collectEffectsFromExpr(ee.condition, effects);
            },
            .match_expr => |me| {
                try self.collectEffectsFromExpr(me.value, effects);
                for (me.arms) |arm| {
                    try self.collectEffectsFromExpr(arm.body, effects);
                }
            },
            else => {},
        }
    }

    pub fn isCapabilityForEffect(self: *EffectChecker, type_annotation: ast.Type, effect: types.Effect) bool {
        _ = self;
        if (type_annotation != .simple) return false;
        const type_name = type_annotation.simple.name;

        const capability_name = switch (effect) {
            .fs => "Fs",
            .net => "Net",
            .io => "Io",
            .time => "Time",
            .rng => "Rng",
            .alloc => "Alloc",
            .cpu => "Cpu",
            .atomics => "Atomics",
            .simd => "Simd",
            .ffi => "Ffi",
        };

        return std.mem.eql(u8, type_name, capability_name);
    }

    pub fn requiresCapability(self: *EffectChecker, effect: types.Effect) bool {
        _ = self;
        return switch (effect) {
            .fs, .net, .io, .time, .rng, .ffi => true,
            .alloc, .cpu, .atomics, .simd => false,
        };
    }

    fn getCapabilityTypeName(self: *EffectChecker, effect: types.Effect) []const u8 {
        _ = self;
        return switch (effect) {
            .fs => "Fs",
            .net => "Net",
            .io => "Io",
            .time => "Time",
            .rng => "Rng",
            .alloc => "Alloc",
            .cpu => "Cpu",
            .atomics => "Atomics",
            .simd => "Simd",
            .ffi => "Ffi",
        };
    }

    pub fn isAmbientCapability(self: *EffectChecker, effect: types.Effect) bool {
        _ = self;
        return switch (effect) {
            .io, .fs, .net, .time, .rng => true,
            .alloc, .cpu, .atomics, .simd, .ffi => false,
        };
    }
};

test {
}
