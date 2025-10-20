const std = @import("std");
const types = @import("types.zig");
const ast = @import("ast.zig");

pub const Position = struct {
    line: usize,
    column: usize,

    pub fn contains(self: Position, line: usize, col: usize, length: usize) bool {
        if (line != self.line) {
            return false;
        }
        return col >= self.column and col < self.column + length;
    }
};

pub const HoverKind = enum {
    variable,
    constant,
    parameter,
    function,
    type_def,
    error_domain,
};

pub const FunctionInfo = struct {
    params: []types.ResolvedType,
    param_names: [][]const u8,
    return_type: types.ResolvedType,
    effects: []types.Effect,
    error_domain: ?[]const u8,
};

pub const DomainVariantInfo = struct {
    name: []const u8,
    field_names: [][]const u8,
    field_types: []types.ResolvedType,
};

pub const DomainInfo = struct {
    variants: []DomainVariantInfo,
};

pub const HoverInfo = struct {
    line: usize,
    column: usize,
    length: usize,
    name: []const u8,
    kind: HoverKind,
    resolved_type: types.ResolvedType,
    function_info: ?FunctionInfo,
    domain_info: ?DomainInfo,
};

pub const HoverInfoTable = struct {
    infos: std.ArrayList(HoverInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HoverInfoTable {
        return .{
            .infos = std.ArrayList(HoverInfo){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HoverInfoTable) void {
        // free all copied strings and cloned types
        for (self.infos.items) |info| {
            self.allocator.free(info.name);

            // deinit the resolved type
            info.resolved_type.deinit(self.allocator);

            if (info.function_info) |func_info| {
                for (func_info.param_names) |param_name| {
                    self.allocator.free(param_name);
                }
                self.allocator.free(func_info.param_names);

                // deinit cloned param types
                for (func_info.params) |*param| {
                    param.deinit(self.allocator);
                }
                self.allocator.free(func_info.params);

                self.allocator.free(func_info.effects);
                if (func_info.error_domain) |domain| {
                    self.allocator.free(domain);
                }
            }

            if (info.domain_info) |domain_info| {
                for (domain_info.variants) |variant| {
                    self.allocator.free(variant.name);
                    for (variant.field_names) |field_name| {
                        self.allocator.free(field_name);
                    }
                    self.allocator.free(variant.field_names);
                    for (variant.field_types) |*field_type| {
                        field_type.deinit(self.allocator);
                    }
                    self.allocator.free(variant.field_types);
                }
                self.allocator.free(domain_info.variants);
            }
        }

        self.infos.deinit(self.allocator);
    }

    pub fn add(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, kind: HoverKind, resolved_type: types.ResolvedType) !void {
        // copy name to ensure it survives after AST is destroyed
        const name_copy = try self.allocator.dupe(u8, name);

        // clone the type to ensure it survives after AST is destroyed
        const type_copy = try resolved_type.clone(self.allocator);

        try self.infos.append(self.allocator, .{
            .line = line,
            .column = column,
            .length = length,
            .name = name_copy,
            .kind = kind,
            .resolved_type = type_copy,
            .function_info = null,
            .domain_info = null,
        });
    }

    pub fn addFunction(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, params: []types.ResolvedType, param_names: [][]const u8, return_type: types.ResolvedType, effects: []types.Effect, error_domain: ?[]const u8) !void {
        // deep copy param_names to ensure they survive after AST is destroyed
        const param_names_copy = try self.allocator.alloc([]const u8, param_names.len);
        for (param_names, 0..) |param_name, i| {
            param_names_copy[i] = try self.allocator.dupe(u8, param_name);
        }

        // deep copy params array to ensure types survive after AST is destroyed
        const params_copy = try self.allocator.alloc(types.ResolvedType, params.len);
        for (params, 0..) |param, i| {
            params_copy[i] = try param.clone(self.allocator);
        }

        // deep copy return type
        const return_type_copy = try return_type.clone(self.allocator);

        // deep copy effects array
        const effects_copy = try self.allocator.dupe(types.Effect, effects);

        // deep copy error_domain if present
        const error_domain_copy = if (error_domain) |domain|
            try self.allocator.dupe(u8, domain)
        else
            null;

        // copy name
        const name_copy = try self.allocator.dupe(u8, name);

        try self.infos.append(self.allocator, .{
            .line = line,
            .column = column,
            .length = length,
            .name = name_copy,
            .kind = .function,
            .resolved_type = return_type_copy,
            .function_info = .{
                .params = params_copy,
                .param_names = param_names_copy,
                .return_type = return_type_copy,
                .effects = effects_copy,
                .error_domain = error_domain_copy,
            },
            .domain_info = null,
        });
    }

    pub fn addDomain(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, variants: []DomainVariantInfo) !void {
        // copy name to ensure it survives after AST is destroyed
        const name_copy = try self.allocator.dupe(u8, name);

        // deep copy variant info
        const variants_copy = try self.allocator.alloc(DomainVariantInfo, variants.len);
        for (variants, 0..) |variant, i| {
            const variant_name_copy = try self.allocator.dupe(u8, variant.name);

            const field_names_copy = try self.allocator.alloc([]const u8, variant.field_names.len);
            for (variant.field_names, 0..) |field_name, j| {
                field_names_copy[j] = try self.allocator.dupe(u8, field_name);
            }

            // clone field types to ensure they survive after AST is destroyed
            const field_types_copy = try self.allocator.alloc(types.ResolvedType, variant.field_types.len);
            for (variant.field_types, 0..) |field_type, j| {
                field_types_copy[j] = try field_type.clone(self.allocator);
            }

            variants_copy[i] = .{
                .name = variant_name_copy,
                .field_names = field_names_copy,
                .field_types = field_types_copy,
            };
        }

        try self.infos.append(self.allocator, .{
            .line = line,
            .column = column,
            .length = length,
            .name = name_copy,
            .kind = .error_domain,
            .resolved_type = .unit_type,
            .function_info = null,
            .domain_info = .{
                .variants = variants_copy,
            },
        });
    }

    pub fn findAt(self: *const HoverInfoTable, line: usize, col: usize) ?HoverInfo {
        for (self.infos.items) |info| {
            if (info.line == line and col >= info.column and col < info.column + info.length) {
                return info;
            }
        }
        return null;
    }
};
