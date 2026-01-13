const std = @import("std");
const types = @import("types.zig");
const context = @import("context.zig");

pub const Symbol = union(enum) {
    function: FunctionSymbol,
    variable: VariableSymbol,
    constant: ConstantSymbol,
    type_def: TypeSymbol,
    domain: DomainSymbol,
    parameter: ParameterSymbol,
    error_type: ErrorTypeSymbol,

    pub fn getName(self: *const Symbol) []const u8 {
        return switch (self.*) {
            .function => |f| f.name,
            .variable => |v| v.name,
            .constant => |c| c.name,
            .type_def => |t| t.name,
            .domain => |d| d.name,
            .parameter => |p| p.name,
            .error_type => |e| e.name,
        };
    }

    /// returns a tag name for this symbol kind (no allocations)
    pub fn kindName(self: *const Symbol) []const u8 {
        return switch (self.*) {
            .function => "function",
            .variable => "variable",
            .constant => "constant",
            .type_def => "type",
            .domain => "domain",
            .parameter => "parameter",
            .error_type => "error",
        };
    }

    /// dumps the symbol for debugging
    pub fn dump(self: *const Symbol, allocator: std.mem.Allocator) void {
        const name = self.getName();
        const kind = self.kindName();

        switch (self.*) {
            .function => |f| {
                const ret_str = f.return_type.toStr(allocator) catch "?";
                defer if (ret_str.len > 0 and ret_str[0] != '?') allocator.free(ret_str);
                std.debug.print("[Symbol] {s} {s}(...) -> {s}\n", .{ kind, name, ret_str });
            },
            .variable => |v| {
                const type_str = v.type_annotation.toStr(allocator) catch "?";
                defer if (type_str.len > 0 and type_str[0] != '?') allocator.free(type_str);
                std.debug.print("[Symbol] {s} {s}: {s} (mutable={}, scope={})\n", .{ kind, name, type_str, v.is_mutable, v.scope_level });
            },
            .constant => |c| {
                const type_str = c.type_annotation.toStr(allocator) catch "?";
                defer if (type_str.len > 0 and type_str[0] != '?') allocator.free(type_str);
                std.debug.print("[Symbol] {s} {s}: {s} (scope={})\n", .{ kind, name, type_str, c.scope_level });
            },
            .type_def => |t| {
                const type_str = t.underlying.toStr(allocator) catch "?";
                defer if (type_str.len > 0 and type_str[0] != '?') allocator.free(type_str);
                std.debug.print("[Symbol] {s} {s} = {s}\n", .{ kind, name, type_str });
            },
            .parameter => |p| {
                const type_str = p.type_annotation.toStr(allocator) catch "?";
                defer if (type_str.len > 0 and type_str[0] != '?') allocator.free(type_str);
                std.debug.print("[Symbol] {s} {s}: {s} (inout={}, cap={})\n", .{ kind, name, type_str, p.is_inout, p.is_capability });
            },
            .domain => {
                std.debug.print("[Symbol] {s} {s}\n", .{ kind, name });
            },
            .error_type => {
                std.debug.print("[Symbol] {s} {s}\n", .{ kind, name });
            },
        }
    }
};

pub const FunctionSymbol = struct {
    name: []const u8,
    type_params: ?[]types.TypeParamInfo,
    params: []types.ResolvedType,
    param_names: [][]const u8,
    return_type: types.ResolvedType,
    effects: []types.Effect,
    error_domain: ?[]const u8,
    is_capability_param: []bool,
};

pub const VariableSymbol = struct {
    name: []const u8,
    type_annotation: types.ResolvedType,
    is_mutable: bool,
    scope_level: u32,
};

pub const ConstantSymbol = struct {
    name: []const u8,
    type_annotation: types.ResolvedType,
    scope_level: u32,
};

pub const TypeSymbol = struct {
    name: []const u8,
    type_params: ?[]types.TypeParamInfo,
    underlying: types.ResolvedType,
};

pub const DomainSymbol = struct {
    name: []const u8,
};

pub const ParameterSymbol = struct {
    name: []const u8,
    type_annotation: types.ResolvedType,
    is_inout: bool,
    is_capability: bool,
};

pub const ErrorTypeSymbol = struct {
    name: []const u8,
};

pub const Scope = struct {
    parent: ?*Scope,
    symbols: std.StringHashMap(Symbol),
    scope_level: u32,
    allocator: std.mem.Allocator,

    // compilation context for interning
    // types and strings are borrowed from the context's arena
    compilation_context: *context.CompilationContext,

    pub fn init(ctx: *context.CompilationContext, parent: ?*Scope, scope_level: u32) Scope {
        return .{
            .parent = parent,
            .symbols = std.StringHashMap(Symbol).init(ctx.permanentAllocator()),
            .scope_level = scope_level,
            .allocator = ctx.permanentAllocator(),
            .compilation_context = ctx,
        };
    }

    pub fn insert(self: *Scope, name: []const u8, symbol: Symbol) !void {
        try self.symbols.put(name, symbol);
    }

    pub fn lookup(self: *const Scope, name: []const u8) ?Symbol {
        if (self.symbols.get(name)) |symbol| {
            return symbol;
        }

        if (self.parent) |parent| {
            return parent.lookup(name);
        }

        return null;
    }

    pub fn lookupLocal(self: *const Scope, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    pub fn deinit(self: *Scope) void {
        // arena cleanup handles type memory; only the hashmap structure needs deinit
        self.symbols.deinit();
    }

    /// dumps all symbols in this scope for debugging
    pub fn dump(self: *const Scope) void {
        std.debug.print("[Scope level={}] {} symbols\n", .{ self.scope_level, self.symbols.count() });
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  '{s}': {s}\n", .{ entry.key_ptr.*, entry.value_ptr.kindName() });
        }
    }

    /// dumps all symbols in this scope with full type information
    pub fn dumpFull(self: *const Scope) void {
        std.debug.print("[Scope level={}] {} symbols\n", .{ self.scope_level, self.symbols.count() });
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  ", .{});
            entry.value_ptr.dump(self.allocator);
        }
    }
};

const BuiltinParam = struct {
    name: []const u8,
    param_type: types.ResolvedType,
};

const BuiltinDef = struct {
    name: []const u8,
    params: []const BuiltinParam,
    return_type: types.ResolvedType,
    effects: []const types.Effect,
};

const builtins = [_]BuiltinDef{
    // basic print functions
    .{ .name = "println", .params = &.{.{ .name = "str", .param_type = .string_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print", .params = &.{.{ .name = "str", .param_type = .string_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_i8", .params = &.{.{ .name = "value", .param_type = .i8 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_i32", .params = &.{.{ .name = "value", .param_type = .i32 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_i64", .params = &.{.{ .name = "value", .param_type = .i64 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_f64", .params = &.{.{ .name = "value", .param_type = .f64 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_bool", .params = &.{.{ .name = "value", .param_type = .bool_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_newline", .params = &.{}, .return_type = .unit_type, .effects = &.{.io} },
    // debug print functions (prints label = value with newline)
    .{ .name = "dbg_i32", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "value", .param_type = .i32 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "dbg_i64", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "value", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "dbg_f64", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "value", .param_type = .f64 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "dbg_bool", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "value", .param_type = .bool_type } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "dbg_str", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "value", .param_type = .string_type } }, .return_type = .unit_type, .effects = &.{.io} },
    // result printing (prints "ok: value" or "err: code")
    .{ .name = "print_result_i32", .params = &.{ .{ .name = "tag", .param_type = .i8 }, .{ .name = "value", .param_type = .i32 }, .{ .name = "error_code", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_result_i64", .params = &.{ .{ .name = "tag", .param_type = .i8 }, .{ .name = "value", .param_type = .i64 }, .{ .name = "error_code", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_result_f64", .params = &.{ .{ .name = "tag", .param_type = .i8 }, .{ .name = "value", .param_type = .f64 }, .{ .name = "error_code", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_result_bool", .params = &.{ .{ .name = "tag", .param_type = .i8 }, .{ .name = "value", .param_type = .bool_type }, .{ .name = "error_code", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    // debug result printing (prints "label = ok: value" or "label = err: code")
    .{ .name = "dbg_result_i32", .params = &.{ .{ .name = "label", .param_type = .string_type }, .{ .name = "tag", .param_type = .i8 }, .{ .name = "value", .param_type = .i32 }, .{ .name = "error_code", .param_type = .i64 } }, .return_type = .unit_type, .effects = &.{.io} },
    // input
    .{ .name = "read_char", .params = &.{}, .return_type = .i32, .effects = &.{.io} },
};

pub const SymbolTable = struct {
    global_scope: Scope,
    allocator: std.mem.Allocator,

    // compilation context for interning
    compilation_context: *context.CompilationContext,

    pub fn init(ctx: *context.CompilationContext) SymbolTable {
        var table = SymbolTable{
            .global_scope = Scope.init(ctx, null, 0),
            .allocator = ctx.permanentAllocator(),
            .compilation_context = ctx,
        };
        table.registerBuiltins() catch {};
        return table;
    }

    fn registerBuiltins(self: *SymbolTable) !void {
        for (builtins) |builtin| {
            const param_types = try self.allocator.alloc(types.ResolvedType, builtin.params.len);
            const param_names = try self.allocator.alloc([]const u8, builtin.params.len);
            const is_capability = try self.allocator.alloc(bool, builtin.params.len);

            for (builtin.params, 0..) |param, i| {
                param_types[i] = param.param_type;
                param_names[i] = param.name;
                is_capability[i] = false;
            }

            try self.insertGlobal(builtin.name, Symbol{
                .function = FunctionSymbol{
                    .name = builtin.name,
                    .type_params = null,
                    .params = param_types,
                    .param_names = param_names,
                    .return_type = builtin.return_type,
                    .effects = try self.allocator.dupe(types.Effect, builtin.effects),
                    .error_domain = null,
                    .is_capability_param = is_capability,
                },
            });
        }
    }

    pub fn isBuiltin(name: []const u8) bool {
        for (builtins) |builtin| {
            if (std.mem.eql(u8, name, builtin.name)) {
                return true;
            }
        }
        return false;
    }

    pub fn insertGlobal(self: *SymbolTable, name: []const u8, symbol: Symbol) !void {
        try self.global_scope.insert(name, symbol);
    }

    pub fn lookupGlobal(self: *const SymbolTable, name: []const u8) ?Symbol {
        return self.global_scope.lookup(name);
    }

    pub fn deinit(self: *SymbolTable) void {
        // arena cleanup handles type memory; only the hashmap structure needs deinit
        self.global_scope.deinit();
    }

    /// dumps the symbol table for debugging (summary view)
    pub fn dump(self: *const SymbolTable) void {
        std.debug.print("[SymbolTable] global scope:\n", .{});
        self.global_scope.dump();
    }

    /// dumps the symbol table with full type information
    pub fn dumpFull(self: *const SymbolTable) void {
        std.debug.print("[SymbolTable] global scope (full):\n", .{});
        self.global_scope.dumpFull();
    }
};
