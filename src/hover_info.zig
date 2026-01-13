const std = @import("std");
const types = @import("types.zig");
const ast = @import("ast.zig");
const context = @import("context.zig");

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
    field,
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

pub const FieldDefinitionLoc = struct {
    line: usize,
    column: usize,
    length: usize,
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
    field_def_loc: ?FieldDefinitionLoc,
};

pub const HoverInfoTable = struct {
    infos: std.ArrayList(HoverInfo),
    allocator: std.mem.Allocator,

    // compilation context for interning
    // strings and types are borrowed from the context's arena
    compilation_context: *context.CompilationContext,

    pub fn init(ctx: *context.CompilationContext) HoverInfoTable {
        return .{
            .infos = std.ArrayList(HoverInfo){},
            .allocator = ctx.permanentAllocator(),
            .compilation_context = ctx,
        };
    }

    pub fn deinit(self: *HoverInfoTable) void {
        // arena cleanup handles type memory; only the arraylist structure needs explicit cleanup
        self.infos.deinit(self.allocator);
    }

    // interns a string in the context's arena
    fn internString(self: *HoverInfoTable, str: []const u8) ![]const u8 {
        return self.compilation_context.internString(str);
    }

    // interns a type in the context's arena
    fn internType(self: *HoverInfoTable, resolved_type: types.ResolvedType) !types.ResolvedType {
        const interned = try self.compilation_context.internType(resolved_type);
        return interned.*;
    }

    pub fn add(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, kind: HoverKind, resolved_type: types.ResolvedType) !void {
        try self.addWithFieldDef(line, column, length, name, kind, resolved_type, null);
    }

    pub fn addWithFieldDef(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, kind: HoverKind, resolved_type: types.ResolvedType, field_def_loc: ?FieldDefinitionLoc) !void {
        // intern name to ensure it survives after AST is destroyed
        const name_copy = try self.internString(name);

        // intern the type to ensure it survives after AST is destroyed
        const type_copy = try self.internType(resolved_type);

        try self.infos.append(self.allocator, .{
            .line = line,
            .column = column,
            .length = length,
            .name = name_copy,
            .kind = kind,
            .resolved_type = type_copy,
            .function_info = null,
            .domain_info = null,
            .field_def_loc = field_def_loc,
        });
    }

    pub fn addFunction(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, params: []types.ResolvedType, param_names: [][]const u8, return_type: types.ResolvedType, effects: []types.Effect, error_domain: ?[]const u8) !void {
        // intern or copy param_names to ensure they survive after AST is destroyed
        const param_names_copy = try self.allocator.alloc([]const u8, param_names.len);
        for (param_names, 0..) |param_name, i| {
            param_names_copy[i] = try self.internString(param_name);
        }

        // intern or clone params array to ensure types survive after AST is destroyed
        const params_copy = try self.allocator.alloc(types.ResolvedType, params.len);
        for (params, 0..) |param, i| {
            params_copy[i] = try self.internType(param);
        }

        // intern or clone return type
        const return_type_copy = try self.internType(return_type);

        // copy effects array (effects are simple enums, always copy)
        const effects_copy = try self.allocator.dupe(types.Effect, effects);

        // intern or copy error_domain if present
        const error_domain_copy: ?[]const u8 = if (error_domain) |domain|
            try self.internString(domain)
        else
            null;

        // intern or copy name
        const name_copy = try self.internString(name);

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
            .field_def_loc = null,
        });
    }

    pub fn addDomain(self: *HoverInfoTable, line: usize, column: usize, length: usize, name: []const u8, variants: []DomainVariantInfo) !void {
        // intern or copy name to ensure it survives after AST is destroyed
        const name_copy = try self.internString(name);

        // deep copy variant info with interning where possible
        const variants_copy = try self.allocator.alloc(DomainVariantInfo, variants.len);
        for (variants, 0..) |variant, i| {
            const variant_name_copy = try self.internString(variant.name);

            const field_names_copy = try self.allocator.alloc([]const u8, variant.field_names.len);
            for (variant.field_names, 0..) |field_name, j| {
                field_names_copy[j] = try self.internString(field_name);
            }

            // intern or clone field types to ensure they survive after AST is destroyed
            const field_types_copy = try self.allocator.alloc(types.ResolvedType, variant.field_types.len);
            for (variant.field_types, 0..) |field_type, j| {
                field_types_copy[j] = try self.internType(field_type);
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
            .field_def_loc = null,
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
