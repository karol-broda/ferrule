const std = @import("std");
const types = @import("types.zig");

pub const Symbol = union(enum) {
    function: FunctionSymbol,
    variable: VariableSymbol,
    constant: ConstantSymbol,
    type_def: TypeSymbol,
    domain: DomainSymbol,
    parameter: ParameterSymbol,
    role: RoleSymbol,

    pub fn getName(self: *const Symbol) []const u8 {
        return switch (self.*) {
            .function => |f| f.name,
            .variable => |v| v.name,
            .constant => |c| c.name,
            .type_def => |t| t.name,
            .domain => |d| d.name,
            .parameter => |p| p.name,
            .role => |r| r.name,
        };
    }
};

pub const FunctionSymbol = struct {
    name: []const u8,
    params: []types.ResolvedType,
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

pub const RoleSymbol = struct {
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
        self.symbols.deinit();
    }
};

pub const SymbolTable = struct {
    global_scope: Scope,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{
            .global_scope = Scope.init(allocator, null, 0),
            .allocator = allocator,
        };
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
                    self.allocator.free(f.params);
                    self.allocator.free(f.effects);
                    self.allocator.free(f.is_capability_param);
                },
                else => {},
            }
        }
        self.global_scope.deinit();
    }
};
