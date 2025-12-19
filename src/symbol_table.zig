const std = @import("std");
const types = @import("types.zig");

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

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope, scope_level: u32) Scope {
        return .{
            .parent = parent,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .scope_level = scope_level,
            .allocator = allocator,
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
        // free type annotations in symbols to prevent memory leaks
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .variable => |v| {
                    v.type_annotation.deinit(self.allocator);
                },
                .constant => |c| {
                    c.type_annotation.deinit(self.allocator);
                },
                .parameter => |p| {
                    p.type_annotation.deinit(self.allocator);
                },
                else => {},
            }
        }
        self.symbols.deinit();
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
    .{ .name = "println", .params = &.{.{ .name = "str", .param_type = .string_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print", .params = &.{.{ .name = "str", .param_type = .string_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_i32", .params = &.{.{ .name = "value", .param_type = .i32 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_i64", .params = &.{.{ .name = "value", .param_type = .i64 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_f64", .params = &.{.{ .name = "value", .param_type = .f64 }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_bool", .params = &.{.{ .name = "value", .param_type = .bool_type }}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "print_newline", .params = &.{}, .return_type = .unit_type, .effects = &.{.io} },
    .{ .name = "read_char", .params = &.{}, .return_type = .i32, .effects = &.{.io} },
};

pub const SymbolTable = struct {
    global_scope: Scope,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        var table = SymbolTable{
            .global_scope = Scope.init(allocator, null, 0),
            .allocator = allocator,
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
        var iter = self.global_scope.symbols.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .function => |f| {
                    // deinit each parameter type before freeing the array
                    for (f.params) |*param| {
                        param.deinit(self.allocator);
                    }
                    self.allocator.free(f.params);
                    self.allocator.free(f.param_names);

                    // deinit return type
                    f.return_type.deinit(self.allocator);

                    self.allocator.free(f.effects);
                    self.allocator.free(f.is_capability_param);
                },
                .type_def => |td| {
                    td.underlying.deinit(self.allocator);
                },
                .variable => |v| {
                    v.type_annotation.deinit(self.allocator);
                },
                .constant => |c| {
                    c.type_annotation.deinit(self.allocator);
                },
                .parameter => |p| {
                    p.type_annotation.deinit(self.allocator);
                },
                else => {},
            }
        }
        self.global_scope.deinit();
    }
};
