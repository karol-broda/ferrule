const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const diagnostics = @import("../diagnostics.zig");
const context = @import("../context.zig");

pub const TypeParamContext = struct {
    type_param_names: []const []const u8,
    is_const: []const bool,

    pub fn empty() TypeParamContext {
        return .{
            .type_param_names = &[_][]const u8{},
            .is_const = &[_]bool{},
        };
    }

    pub fn findTypeParam(self: TypeParamContext, name: []const u8) ?usize {
        for (self.type_param_names, 0..) |tp_name, i| {
            if (std.mem.eql(u8, tp_name, name)) {
                return i;
            }
        }
        return null;
    }
};

pub const TypeResolver = struct {
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *diagnostics.DiagnosticList,
    allocator: std.mem.Allocator,
    source_file: []const u8,
    type_param_context: TypeParamContext,

    // compilation context for arena-based memory management
    // resolved types are interned for deduplication
    compilation_context: *context.CompilationContext,

    pub fn init(
        ctx: *context.CompilationContext,
        symbols: *symbol_table.SymbolTable,
        diagnostics_list: *diagnostics.DiagnosticList,
        source_file: []const u8,
    ) TypeResolver {
        return .{
            .symbols = symbols,
            .diagnostics_list = diagnostics_list,
            .allocator = ctx.permanentAllocator(),
            .source_file = source_file,
            .type_param_context = TypeParamContext.empty(),
            .compilation_context = ctx,
        };
    }

    // interns a type in the context's arena
    fn internType(self: *TypeResolver, resolved_type: types.ResolvedType) !types.ResolvedType {
        const interned = try self.compilation_context.internType(resolved_type);
        return interned.*;
    }

    // interns a string in the context's arena
    fn internString(self: *TypeResolver, str: []const u8) ![]const u8 {
        return self.compilation_context.internString(str);
    }

    pub fn setTypeParamContext(self: *TypeResolver, ctx: TypeParamContext) void {
        self.type_param_context = ctx;
    }

    pub fn clearTypeParamContext(self: *TypeResolver) void {
        self.type_param_context = TypeParamContext.empty();
    }

    pub fn resolve(self: *TypeResolver, type_expr: ast.Type) std.mem.Allocator.Error!types.ResolvedType {
        return switch (type_expr) {
            .simple => |simple| try self.resolveSimple(simple),
            .generic => |gen| try self.resolveGeneric(gen),
            .array => |arr| try self.resolveArray(arr),
            .vector => |vec| try self.resolveVector(vec),
            .view => |view| try self.resolveView(view),
            .nullable => |nullable| try self.resolveNullable(nullable),
            .function_type => |ft| try self.resolveFunctionType(ft),
            .record_type => |rt| try self.resolveRecordType(rt),
            .union_type => |ut| try self.resolveUnionType(ut),
        };
    }

    fn resolveSimple(self: *TypeResolver, simple: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const name = simple.name;
        const loc = simple.loc;

        // first check if this is a type parameter in scope
        if (self.type_param_context.findTypeParam(name)) |index| {
            return types.ResolvedType{
                .type_param = .{
                    .name = name,
                    .index = index,
                },
            };
        }

        const primitive_types = std.StaticStringMap(types.ResolvedType).initComptime(.{
            .{ "i8", .i8 },
            .{ "i16", .i16 },
            .{ "i32", .i32 },
            .{ "i64", .i64 },
            .{ "i128", .i128 },
            .{ "u8", .u8 },
            .{ "u16", .u16 },
            .{ "u32", .u32 },
            .{ "u64", .u64 },
            .{ "u128", .u128 },
            .{ "usize", .usize_type },
            .{ "f16", .f16 },
            .{ "f32", .f32 },
            .{ "f64", .f64 },
            .{ "Bool", .bool_type },
            .{ "Char", .char_type },
            .{ "String", .string_type },
            .{ "Bytes", .bytes_type },
            .{ "Fs", .fs_cap },
            .{ "Net", .net_cap },
            .{ "Io", .io_cap },
            .{ "Time", .time_cap },
            .{ "Rng", .rng_cap },
            .{ "Alloc", .alloc_cap },
            .{ "Cpu", .cpu_cap },
            .{ "Atomics", .atomics_cap },
            .{ "Simd", .simd_cap },
            .{ "Ffi", .ffi_cap },
        });

        if (primitive_types.get(name)) |primitive| {
            return primitive;
        }

        if (self.symbols.lookupGlobal(name)) |symbol| {
            switch (symbol) {
                .type_def => |td| {
                    // types are arena-managed, no clone needed
                    const underlying_ptr = try self.allocator.create(types.ResolvedType);
                    underlying_ptr.* = td.underlying;
                    // intern the named type for deduplication
                    return try self.internType(types.ResolvedType{
                        .named = .{
                            .name = td.name,
                            .underlying = underlying_ptr,
                        },
                    });
                },
                else => {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "'{s}' is not a type",
                            .{name},
                        ),
                        .{
                            .file = self.source_file,
                            .line = loc.line,
                            .column = loc.column,
                            .length = name.len,
                        },
                        null,
                    );
                    return types.ResolvedType.unit_type;
                },
            }
        }

        try self.diagnostics_list.addError(
            try std.fmt.allocPrint(
                self.allocator,
                "unknown type '{s}'",
                .{name},
            ),
            .{
                .file = self.source_file,
                .line = loc.line,
                .column = loc.column,
                .length = name.len,
            },
            null,
        );
        return types.ResolvedType.unit_type;
    }

    fn resolveGeneric(self: *TypeResolver, gen: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const name = gen.name;

        // handle built-in generic types
        if (std.mem.eql(u8, name, "Array")) {
            if (gen.type_args.len < 1 or gen.type_args.len > 2) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Array expects 1 or 2 type arguments (Array<T> or Array<T, n>), got {d}",
                        .{gen.type_args.len},
                    ),
                    .{
                        .file = self.source_file,
                        .line = gen.loc.line,
                        .column = gen.loc.column,
                        .length = name.len,
                    },
                    null,
                );
                return types.ResolvedType.unit_type;
            }

            const element_type_ptr = try self.allocator.create(types.ResolvedType);
            errdefer self.allocator.destroy(element_type_ptr);
            element_type_ptr.* = try self.resolve(gen.type_args[0]);

            var size: usize = 0;
            if (gen.type_args.len == 2) {
                size = try self.evaluateTypeArgAsSize(gen.type_args[1]);
            }

            return types.ResolvedType{
                .array = .{
                    .element_type = element_type_ptr,
                    .size = size,
                },
            };
        }

        if (std.mem.eql(u8, name, "Vector")) {
            if (gen.type_args.len < 1 or gen.type_args.len > 2) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Vector expects 1 or 2 type arguments (Vector<T> or Vector<T, n>), got {d}",
                        .{gen.type_args.len},
                    ),
                    .{
                        .file = self.source_file,
                        .line = gen.loc.line,
                        .column = gen.loc.column,
                        .length = name.len,
                    },
                    null,
                );
                return types.ResolvedType.unit_type;
            }

            const element_type_ptr = try self.allocator.create(types.ResolvedType);
            errdefer self.allocator.destroy(element_type_ptr);
            element_type_ptr.* = try self.resolve(gen.type_args[0]);

            var size: usize = 0;
            if (gen.type_args.len == 2) {
                size = try self.evaluateTypeArgAsSize(gen.type_args[1]);
            }

            return types.ResolvedType{
                .vector = .{
                    .element_type = element_type_ptr,
                    .size = size,
                },
            };
        }

        if (std.mem.eql(u8, name, "View")) {
            if (gen.type_args.len != 1) {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "View expects 1 type argument, got {d}",
                        .{gen.type_args.len},
                    ),
                    .{
                        .file = self.source_file,
                        .line = gen.loc.line,
                        .column = gen.loc.column,
                        .length = name.len,
                    },
                    null,
                );
                return types.ResolvedType.unit_type;
            }

            const element_type_ptr = try self.allocator.create(types.ResolvedType);
            errdefer self.allocator.destroy(element_type_ptr);
            element_type_ptr.* = try self.resolve(gen.type_args[0]);

            return types.ResolvedType{
                .view = .{
                    .element_type = element_type_ptr,
                    .mutable = false,
                },
            };
        }

        // unknown generic type
        try self.diagnostics_list.addError(
            try std.fmt.allocPrint(
                self.allocator,
                "unknown generic type '{s}'",
                .{name},
            ),
            .{
                .file = self.source_file,
                .line = gen.loc.line,
                .column = gen.loc.column,
                .length = name.len,
            },
            null,
        );
        return types.ResolvedType.unit_type;
    }

    fn resolveArray(self: *TypeResolver, arr: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const element_type_ptr = try self.allocator.create(types.ResolvedType);
        errdefer self.allocator.destroy(element_type_ptr);
        element_type_ptr.* = try self.resolve(arr.element_type.*);

        const size = try self.evaluateConstExpr(arr.size);

        return types.ResolvedType{
            .array = .{
                .element_type = element_type_ptr,
                .size = size,
            },
        };
    }

    fn resolveVector(self: *TypeResolver, vec: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const element_type_ptr = try self.allocator.create(types.ResolvedType);
        errdefer self.allocator.destroy(element_type_ptr);
        element_type_ptr.* = try self.resolve(vec.element_type.*);

        const size = try self.evaluateConstExpr(vec.size);

        return types.ResolvedType{
            .vector = .{
                .element_type = element_type_ptr,
                .size = size,
            },
        };
    }

    fn resolveView(self: *TypeResolver, view: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const element_type_ptr = try self.allocator.create(types.ResolvedType);
        errdefer self.allocator.destroy(element_type_ptr);
        element_type_ptr.* = try self.resolve(view.element_type.*);

        return types.ResolvedType{
            .view = .{
                .element_type = element_type_ptr,
                .mutable = view.mutable,
            },
        };
    }

    fn resolveNullable(self: *TypeResolver, nullable: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const inner_type_ptr = try self.allocator.create(types.ResolvedType);
        errdefer self.allocator.destroy(inner_type_ptr);
        inner_type_ptr.* = try self.resolve(nullable.inner.*);

        return types.ResolvedType{
            .nullable = inner_type_ptr,
        };
    }

    fn resolveFunctionType(self: *TypeResolver, ft: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const params = try self.allocator.alloc(types.ResolvedType, ft.params.len);
        for (ft.params, 0..) |param, i| {
            params[i] = try self.resolve(param);
        }

        const return_type_ptr = try self.allocator.create(types.ResolvedType);
        return_type_ptr.* = try self.resolve(ft.return_type.*);

        const effects = try self.allocator.alloc(types.Effect, ft.effects.len);
        for (ft.effects, 0..) |effect_str, i| {
            if (types.Effect.fromString(effect_str)) |effect| {
                effects[i] = effect;
            } else {
                try self.diagnostics_list.addError(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "unknown effect '{s}'",
                        .{effect_str},
                    ),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = effect_str.len,
                    },
                    null,
                );
                self.allocator.free(effects);
                self.allocator.destroy(return_type_ptr);
                self.allocator.free(params);
                return types.ResolvedType.unit_type;
            }
        }

        return types.ResolvedType{
            .function_type = .{
                .params = params,
                .return_type = return_type_ptr,
                .effects = effects,
                .error_domain = ft.error_domain,
                .type_params = null,
            },
        };
    }

    fn resolveRecordType(self: *TypeResolver, rt: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const field_names = try self.allocator.alloc([]const u8, rt.fields.len);
        errdefer self.allocator.free(field_names);

        const field_types = try self.allocator.alloc(types.ResolvedType, rt.fields.len);
        errdefer self.allocator.free(field_types);

        for (rt.fields, 0..) |field, i| {
            field_names[i] = try self.allocator.dupe(u8, field.name);
            field_types[i] = try self.resolve(field.type_annotation);
        }

        return types.ResolvedType{
            .record = .{
                .field_names = field_names,
                .field_types = field_types,
                .field_locations = null,
            },
        };
    }

    fn resolveUnionType(self: *TypeResolver, ut: anytype) std.mem.Allocator.Error!types.ResolvedType {
        const variants = try self.allocator.alloc(types.UnionVariantInfo, ut.variants.len);
        errdefer self.allocator.free(variants);

        for (ut.variants, 0..) |variant, i| {
            const field_count = if (variant.fields) |fields| fields.len else 0;
            const field_names = try self.allocator.alloc([]const u8, field_count);
            const field_types = try self.allocator.alloc(types.ResolvedType, field_count);

            if (variant.fields) |fields| {
                for (fields, 0..) |field, j| {
                    field_names[j] = try self.allocator.dupe(u8, field.name);
                    field_types[j] = try self.resolve(field.type_annotation);
                }
            }

            variants[i] = .{
                .name = try self.allocator.dupe(u8, variant.name),
                .field_names = field_names,
                .field_types = field_types,
            };
        }

        return types.ResolvedType{
            .union_type = .{
                .variants = variants,
            },
        };
    }

    pub fn evaluateConstExpr(self: *TypeResolver, expr: *ast.Expr) !usize {
        switch (expr.*) {
            .number => |num_str| {
                return std.fmt.parseInt(usize, num_str, 10) catch {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "invalid array/vector size: '{s}'",
                            .{num_str},
                        ),
                        .{
                            .file = self.source_file,
                            .line = 0,
                            .column = 0,
                            .length = num_str.len,
                        },
                        try self.allocator.dupe(u8, "size must be a positive integer"),
                    );
                    return 0;
                };
            },
            else => {
                try self.diagnostics_list.addError(
                    try self.allocator.dupe(u8, "array/vector size must be a constant expression"),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
                return 0;
            },
        }
    }

    fn evaluateTypeArgAsSize(self: *TypeResolver, type_arg: ast.Type) !usize {
        switch (type_arg) {
            .simple => |simple| {
                return std.fmt.parseInt(usize, simple.name, 10) catch {
                    try self.diagnostics_list.addError(
                        try std.fmt.allocPrint(
                            self.allocator,
                            "invalid array/vector size: '{s}'",
                            .{simple.name},
                        ),
                        .{
                            .file = self.source_file,
                            .line = simple.loc.line,
                            .column = simple.loc.column,
                            .length = simple.name.len,
                        },
                        try self.allocator.dupe(u8, "size must be a positive integer"),
                    );
                    return 0;
                };
            },
            else => {
                try self.diagnostics_list.addError(
                    try self.allocator.dupe(u8, "array/vector size must be a constant integer"),
                    .{
                        .file = self.source_file,
                        .line = 0,
                        .column = 0,
                        .length = 0,
                    },
                    null,
                );
                return 0;
            },
        }
    }
};

test {}
