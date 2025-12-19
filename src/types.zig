const std = @import("std");

pub const Variance = enum {
    invariant,
    covariant,
    contravariant,
};

pub const TypeParamInfo = struct {
    name: []const u8,
    variance: Variance,
    constraint: ?*ResolvedType,
    is_const: bool,
    const_type: ?*ResolvedType,
};

pub const UnionVariantInfo = struct {
    name: []const u8,
    field_names: []const []const u8,
    field_types: []ResolvedType,
};

pub const ResolvedType = union(enum) {
    i8,
    i16,
    i32,
    i64,
    i128,
    u8,
    u16,
    u32,
    u64,
    u128,
    usize_type,
    f16,
    f32,
    f64,
    bool_type,
    char_type,
    string_type,
    bytes_type,
    unit_type,

    // capability types
    fs_cap,
    net_cap,
    io_cap,
    time_cap,
    rng_cap,
    alloc_cap,
    cpu_cap,
    atomics_cap,
    simd_cap,
    ffi_cap,

    array: struct {
        element_type: *ResolvedType,
        size: usize,
    },
    vector: struct {
        element_type: *ResolvedType,
        size: usize,
    },
    view: struct {
        element_type: *ResolvedType,
        mutable: bool,
    },
    nullable: *ResolvedType,
    function_type: struct {
        params: []ResolvedType,
        return_type: *ResolvedType,
        effects: []Effect,
        error_domain: ?[]const u8,
        type_params: ?[]TypeParamInfo,
    },

    named: struct {
        name: []const u8,
        underlying: *ResolvedType,
    },

    result: struct {
        ok_type: *ResolvedType,
        error_domain: []const u8,
    },

    range: struct {
        element_type: *ResolvedType,
    },

    // generic type support
    type_param: struct {
        name: []const u8,
        index: usize,
    },

    generic_instance: struct {
        base_name: []const u8,
        type_args: []ResolvedType,
        underlying: ?*ResolvedType,
    },

    const_value: struct {
        value: usize,
        const_type: *ResolvedType,
    },

    // record type: { field: Type, field2: Type }
    record: struct {
        field_names: []const []const u8,
        field_types: []ResolvedType,
    },

    // discriminated union: | Variant1 | Variant2 { field: Type }
    union_type: struct {
        variants: []UnionVariantInfo,
    },

    pub fn clone(self: ResolvedType, allocator: std.mem.Allocator) std.mem.Allocator.Error!ResolvedType {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap, .type_param => self,
            .array => |a| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try a.element_type.clone(allocator);
                return ResolvedType{ .array = .{
                    .element_type = elem_ptr,
                    .size = a.size,
                } };
            },
            .vector => |v| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try v.element_type.clone(allocator);
                return ResolvedType{ .vector = .{
                    .element_type = elem_ptr,
                    .size = v.size,
                } };
            },
            .view => |v| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try v.element_type.clone(allocator);
                return ResolvedType{ .view = .{
                    .element_type = elem_ptr,
                    .mutable = v.mutable,
                } };
            },
            .nullable => |n| {
                const inner_ptr = try allocator.create(ResolvedType);
                inner_ptr.* = try n.clone(allocator);
                return ResolvedType{ .nullable = inner_ptr };
            },
            .function_type => |f| {
                const params_copy = try allocator.alloc(ResolvedType, f.params.len);
                for (f.params, 0..) |param, i| {
                    params_copy[i] = try param.clone(allocator);
                }
                const ret_ptr = try allocator.create(ResolvedType);
                ret_ptr.* = try f.return_type.clone(allocator);
                const effects_copy = try allocator.dupe(Effect, f.effects);
                const domain_copy = if (f.error_domain) |domain|
                    try allocator.dupe(u8, domain)
                else
                    null;
                const type_params_copy: ?[]TypeParamInfo = if (f.type_params) |tps| blk: {
                    const copy = try allocator.alloc(TypeParamInfo, tps.len);
                    for (tps, 0..) |tp, i| {
                        copy[i] = .{
                            .name = try allocator.dupe(u8, tp.name),
                            .variance = tp.variance,
                            .constraint = if (tp.constraint) |c| blk2: {
                                const c_ptr = try allocator.create(ResolvedType);
                                c_ptr.* = try c.clone(allocator);
                                break :blk2 c_ptr;
                            } else null,
                            .is_const = tp.is_const,
                            .const_type = if (tp.const_type) |ct| blk3: {
                                const ct_ptr = try allocator.create(ResolvedType);
                                ct_ptr.* = try ct.clone(allocator);
                                break :blk3 ct_ptr;
                            } else null,
                        };
                    }
                    break :blk copy;
                } else null;
                return ResolvedType{ .function_type = .{
                    .params = params_copy,
                    .return_type = ret_ptr,
                    .effects = effects_copy,
                    .error_domain = domain_copy,
                    .type_params = type_params_copy,
                } };
            },
            .named => |n| {
                const under_ptr = try allocator.create(ResolvedType);
                under_ptr.* = try n.underlying.clone(allocator);
                const name_copy = try allocator.dupe(u8, n.name);
                return ResolvedType{ .named = .{
                    .name = name_copy,
                    .underlying = under_ptr,
                } };
            },
            .result => |r| {
                const ok_ptr = try allocator.create(ResolvedType);
                ok_ptr.* = try r.ok_type.clone(allocator);
                const domain_copy = try allocator.dupe(u8, r.error_domain);
                return ResolvedType{ .result = .{
                    .ok_type = ok_ptr,
                    .error_domain = domain_copy,
                } };
            },
            .range => |r| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try r.element_type.clone(allocator);
                return ResolvedType{ .range = .{
                    .element_type = elem_ptr,
                } };
            },
            .generic_instance => |g| {
                const type_args_copy = try allocator.alloc(ResolvedType, g.type_args.len);
                for (g.type_args, 0..) |arg, i| {
                    type_args_copy[i] = try arg.clone(allocator);
                }
                const underlying_copy: ?*ResolvedType = if (g.underlying) |u| blk: {
                    const u_ptr = try allocator.create(ResolvedType);
                    u_ptr.* = try u.clone(allocator);
                    break :blk u_ptr;
                } else null;
                return ResolvedType{ .generic_instance = .{
                    .base_name = try allocator.dupe(u8, g.base_name),
                    .type_args = type_args_copy,
                    .underlying = underlying_copy,
                } };
            },
            .const_value => |cv| {
                const ct_ptr = try allocator.create(ResolvedType);
                ct_ptr.* = try cv.const_type.clone(allocator);
                return ResolvedType{ .const_value = .{
                    .value = cv.value,
                    .const_type = ct_ptr,
                } };
            },
            .record => |r| {
                const names_copy = try allocator.alloc([]const u8, r.field_names.len);
                for (r.field_names, 0..) |name, i| {
                    names_copy[i] = try allocator.dupe(u8, name);
                }
                const types_copy = try allocator.alloc(ResolvedType, r.field_types.len);
                for (r.field_types, 0..) |ft, i| {
                    types_copy[i] = try ft.clone(allocator);
                }
                return ResolvedType{ .record = .{
                    .field_names = names_copy,
                    .field_types = types_copy,
                } };
            },
            .union_type => |u| {
                const variants_copy = try allocator.alloc(UnionVariantInfo, u.variants.len);
                for (u.variants, 0..) |v, i| {
                    const names = try allocator.alloc([]const u8, v.field_names.len);
                    for (v.field_names, 0..) |name, j| {
                        names[j] = try allocator.dupe(u8, name);
                    }
                    const types = try allocator.alloc(ResolvedType, v.field_types.len);
                    for (v.field_types, 0..) |ft, j| {
                        types[j] = try ft.clone(allocator);
                    }
                    variants_copy[i] = .{
                        .name = try allocator.dupe(u8, v.name),
                        .field_names = names,
                        .field_types = types,
                    };
                }
                return ResolvedType{ .union_type = .{
                    .variants = variants_copy,
                } };
            },
        };
    }

    pub fn deinit(self: *const ResolvedType, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap, .type_param => {},
            .array => |a| {
                a.element_type.deinit(allocator);
                allocator.destroy(a.element_type);
            },
            .vector => |v| {
                v.element_type.deinit(allocator);
                allocator.destroy(v.element_type);
            },
            .view => |v| {
                v.element_type.deinit(allocator);
                allocator.destroy(v.element_type);
            },
            .nullable => |n| {
                n.deinit(allocator);
                allocator.destroy(n);
            },
            .function_type => |f| {
                for (f.params) |*param| {
                    param.deinit(allocator);
                }
                allocator.free(f.params);
                f.return_type.deinit(allocator);
                allocator.destroy(f.return_type);
                allocator.free(f.effects);
                if (f.error_domain) |domain| {
                    allocator.free(domain);
                }
                if (f.type_params) |tps| {
                    for (tps) |tp| {
                        allocator.free(tp.name);
                        if (tp.constraint) |c| {
                            c.deinit(allocator);
                            allocator.destroy(c);
                        }
                        if (tp.const_type) |ct| {
                            ct.deinit(allocator);
                            allocator.destroy(ct);
                        }
                    }
                    allocator.free(tps);
                }
            },
            .named => |n| {
                n.underlying.deinit(allocator);
                allocator.destroy(n.underlying);
                allocator.free(n.name);
            },
            .result => |r| {
                r.ok_type.deinit(allocator);
                allocator.destroy(r.ok_type);
                allocator.free(r.error_domain);
            },
            .range => |r| {
                r.element_type.deinit(allocator);
                allocator.destroy(r.element_type);
            },
            .generic_instance => |g| {
                for (g.type_args) |*arg| {
                    arg.deinit(allocator);
                }
                allocator.free(g.type_args);
                if (g.underlying) |u| {
                    u.deinit(allocator);
                    allocator.destroy(u);
                }
                allocator.free(g.base_name);
            },
            .const_value => |cv| {
                cv.const_type.deinit(allocator);
                allocator.destroy(cv.const_type);
            },
            .record => |r| {
                for (r.field_names) |name| {
                    allocator.free(name);
                }
                allocator.free(r.field_names);
                for (r.field_types) |*ft| {
                    ft.deinit(allocator);
                }
                allocator.free(r.field_types);
            },
            .union_type => |u| {
                for (u.variants) |v| {
                    allocator.free(v.name);
                    for (v.field_names) |name| {
                        allocator.free(name);
                    }
                    allocator.free(v.field_names);
                    for (v.field_types) |*ft| {
                        ft.deinit(allocator);
                    }
                    allocator.free(v.field_types);
                }
                allocator.free(u.variants);
            },
        }
    }

    pub fn eql(self: *const ResolvedType, other: *const ResolvedType) bool {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) {
            return false;
        }

        return switch (self.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => true,
            .type_param => |tp| std.mem.eql(u8, tp.name, other.type_param.name),
            .array => |a| {
                const other_array = other.array;
                return a.size == other_array.size and a.element_type.eql(other_array.element_type);
            },
            .vector => |v| {
                const other_vector = other.vector;
                return v.size == other_vector.size and v.element_type.eql(other_vector.element_type);
            },
            .view => |v| {
                const other_view = other.view;
                return v.mutable == other_view.mutable and v.element_type.eql(other_view.element_type);
            },
            .nullable => |n| n.eql(other.nullable),
            .function_type => |f| {
                const other_fn = other.function_type;
                if (f.params.len != other_fn.params.len) return false;
                for (f.params, other_fn.params) |p1, p2| {
                    if (!p1.eql(&p2)) return false;
                }
                if (!f.return_type.eql(other_fn.return_type)) return false;
                if (f.effects.len != other_fn.effects.len) return false;
                for (f.effects, other_fn.effects) |e1, e2| {
                    if (e1 != e2) return false;
                }
                if (f.error_domain != null and other_fn.error_domain != null) {
                    if (!std.mem.eql(u8, f.error_domain.?, other_fn.error_domain.?)) return false;
                } else if (f.error_domain != null or other_fn.error_domain != null) {
                    return false;
                }
                return true;
            },
            .named => |n| std.mem.eql(u8, n.name, other.named.name),
            .result => |r| {
                const other_result = other.result;
                return r.ok_type.eql(other_result.ok_type) and std.mem.eql(u8, r.error_domain, other_result.error_domain);
            },
            .range => |r| r.element_type.eql(other.range.element_type),
            .generic_instance => |g| {
                const other_g = other.generic_instance;
                if (!std.mem.eql(u8, g.base_name, other_g.base_name)) return false;
                if (g.type_args.len != other_g.type_args.len) return false;
                for (g.type_args, other_g.type_args) |a1, a2| {
                    if (!a1.eql(&a2)) return false;
                }
                return true;
            },
            .const_value => |cv| {
                const other_cv = other.const_value;
                return cv.value == other_cv.value and cv.const_type.eql(other_cv.const_type);
            },
            .record => |r| {
                const other_r = other.record;
                if (r.field_names.len != other_r.field_names.len) return false;
                for (r.field_names, other_r.field_names, r.field_types, other_r.field_types) |n1, n2, t1, t2| {
                    if (!std.mem.eql(u8, n1, n2)) return false;
                    if (!t1.eql(&t2)) return false;
                }
                return true;
            },
            .union_type => |u| {
                const other_u = other.union_type;
                if (u.variants.len != other_u.variants.len) return false;
                for (u.variants, other_u.variants) |v1, v2| {
                    if (!std.mem.eql(u8, v1.name, v2.name)) return false;
                    if (v1.field_types.len != v2.field_types.len) return false;
                    for (v1.field_types, v2.field_types) |t1, t2| {
                        if (!t1.eql(&t2)) return false;
                    }
                }
                return true;
            },
        };
    }

    pub fn format(
        self: ResolvedType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .i8 => try writer.writeAll("i8"),
            .i16 => try writer.writeAll("i16"),
            .i32 => try writer.writeAll("i32"),
            .i64 => try writer.writeAll("i64"),
            .i128 => try writer.writeAll("i128"),
            .u8 => try writer.writeAll("u8"),
            .u16 => try writer.writeAll("u16"),
            .u32 => try writer.writeAll("u32"),
            .u64 => try writer.writeAll("u64"),
            .u128 => try writer.writeAll("u128"),
            .usize_type => try writer.writeAll("usize"),
            .f16 => try writer.writeAll("f16"),
            .f32 => try writer.writeAll("f32"),
            .f64 => try writer.writeAll("f64"),
            .bool_type => try writer.writeAll("Bool"),
            .char_type => try writer.writeAll("Char"),
            .string_type => try writer.writeAll("String"),
            .bytes_type => try writer.writeAll("Bytes"),
            .unit_type => try writer.writeAll("()"),
            .fs_cap => try writer.writeAll("Fs"),
            .net_cap => try writer.writeAll("Net"),
            .io_cap => try writer.writeAll("Io"),
            .time_cap => try writer.writeAll("Time"),
            .rng_cap => try writer.writeAll("Rng"),
            .alloc_cap => try writer.writeAll("Alloc"),
            .cpu_cap => try writer.writeAll("Cpu"),
            .atomics_cap => try writer.writeAll("Atomics"),
            .simd_cap => try writer.writeAll("Simd"),
            .ffi_cap => try writer.writeAll("Ffi"),
            .array => |a| {
                if (a.size == 0) {
                    // dynamic sized array - display as Array<T>
                    try writer.writeAll("Array<");
                    try a.element_type.format("", .{}, writer);
                    try writer.writeAll(">");
                } else {
                    // fixed size array
                    try writer.writeAll("Array<");
                    try a.element_type.format("", .{}, writer);
                    try writer.print(", {d}>", .{a.size});
                }
            },
            .vector => |v| {
                if (v.size == 0) {
                    try writer.writeAll("Vector<");
                    try v.element_type.format("", .{}, writer);
                    try writer.writeAll(">");
                } else {
                    try writer.writeAll("Vector<");
                    try v.element_type.format("", .{}, writer);
                    try writer.print(", {d}>", .{v.size});
                }
            },
            .view => |v| {
                try writer.writeAll("View<");
                if (v.mutable) {
                    try writer.writeAll("mut ");
                }
                try v.element_type.format("", .{}, writer);
                try writer.writeAll(">");
            },
            .nullable => |n| {
                try n.format("", .{}, writer);
                try writer.writeAll("?");
            },
            .function_type => |f| {
                try writer.writeAll("(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try p.format("", .{}, writer);
                }
                try writer.writeAll(") -> ");
                try f.return_type.format("", .{}, writer);
            },
            .named => |n| try writer.writeAll(n.name),
            .result => |r| {
                try writer.writeAll("Result<");
                try r.ok_type.format("", .{}, writer);
                try writer.print(", {s}>", .{r.error_domain});
            },
            .range => |r| {
                try writer.writeAll("Range<");
                try r.element_type.format("", .{}, writer);
                try writer.writeAll(">");
            },
            .type_param => |tp| {
                try writer.writeAll(tp.name);
            },
            .generic_instance => |g| {
                try writer.writeAll(g.base_name);
                try writer.writeAll("<");
                for (g.type_args, 0..) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try arg.format("", .{}, writer);
                }
                try writer.writeAll(">");
            },
            .const_value => |cv| {
                try writer.print("{d}", .{cv.value});
            },
            .record => |r| {
                try writer.writeAll("{ ");
                for (r.field_names, r.field_types, 0..) |name, ft, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{s}: ", .{name});
                    try ft.format("", .{}, writer);
                }
                try writer.writeAll(" }");
            },
            .union_type => |u| {
                for (u.variants, 0..) |v, i| {
                    if (i > 0) try writer.writeAll(" ");
                    try writer.print("| {s}", .{v.name});
                    if (v.field_types.len > 0) {
                        try writer.writeAll(" { ");
                        for (v.field_names, v.field_types, 0..) |name, ft, j| {
                            if (j > 0) try writer.writeAll(", ");
                            try writer.print("{s}: ", .{name});
                            try ft.format("", .{}, writer);
                        }
                        try writer.writeAll(" }");
                    }
                }
            },
        }
    }

    // returns a human-readable string representation of the type
    // caller is responsible for freeing the returned string
    pub fn toStr(self: ResolvedType, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        try self.format("", .{}, buf.writer(allocator));
        return buf.toOwnedSlice(allocator);
    }

    /// substitute type parameters with concrete types
    pub fn substitute(self: ResolvedType, type_params: []const []const u8, type_args: []const ResolvedType, allocator: std.mem.Allocator) std.mem.Allocator.Error!ResolvedType {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap, .const_value => self,
            .type_param => |tp| {
                for (type_params, 0..) |param_name, i| {
                    if (std.mem.eql(u8, tp.name, param_name)) {
                        if (i < type_args.len) {
                            return try type_args[i].clone(allocator);
                        }
                    }
                }
                return self;
            },
            .array => |a| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try a.element_type.substitute(type_params, type_args, allocator);
                return ResolvedType{ .array = .{
                    .element_type = elem_ptr,
                    .size = a.size,
                } };
            },
            .vector => |v| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try v.element_type.substitute(type_params, type_args, allocator);
                return ResolvedType{ .vector = .{
                    .element_type = elem_ptr,
                    .size = v.size,
                } };
            },
            .view => |v| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try v.element_type.substitute(type_params, type_args, allocator);
                return ResolvedType{ .view = .{
                    .element_type = elem_ptr,
                    .mutable = v.mutable,
                } };
            },
            .nullable => |n| {
                const inner_ptr = try allocator.create(ResolvedType);
                inner_ptr.* = try n.substitute(type_params, type_args, allocator);
                return ResolvedType{ .nullable = inner_ptr };
            },
            .function_type => |f| {
                const params_copy = try allocator.alloc(ResolvedType, f.params.len);
                for (f.params, 0..) |param, i| {
                    params_copy[i] = try param.substitute(type_params, type_args, allocator);
                }
                const ret_ptr = try allocator.create(ResolvedType);
                ret_ptr.* = try f.return_type.substitute(type_params, type_args, allocator);
                return ResolvedType{
                    .function_type = .{
                        .params = params_copy,
                        .return_type = ret_ptr,
                        .effects = try allocator.dupe(Effect, f.effects),
                        .error_domain = if (f.error_domain) |d| try allocator.dupe(u8, d) else null,
                        .type_params = null,
                    },
                };
            },
            .named => |n| {
                const under_ptr = try allocator.create(ResolvedType);
                under_ptr.* = try n.underlying.substitute(type_params, type_args, allocator);
                return ResolvedType{ .named = .{
                    .name = try allocator.dupe(u8, n.name),
                    .underlying = under_ptr,
                } };
            },
            .result => |r| {
                const ok_ptr = try allocator.create(ResolvedType);
                ok_ptr.* = try r.ok_type.substitute(type_params, type_args, allocator);
                return ResolvedType{ .result = .{
                    .ok_type = ok_ptr,
                    .error_domain = try allocator.dupe(u8, r.error_domain),
                } };
            },
            .range => |r| {
                const elem_ptr = try allocator.create(ResolvedType);
                elem_ptr.* = try r.element_type.substitute(type_params, type_args, allocator);
                return ResolvedType{ .range = .{
                    .element_type = elem_ptr,
                } };
            },
            .generic_instance => |g| {
                const new_type_args = try allocator.alloc(ResolvedType, g.type_args.len);
                for (g.type_args, 0..) |arg, i| {
                    new_type_args[i] = try arg.substitute(type_params, type_args, allocator);
                }
                return ResolvedType{ .generic_instance = .{
                    .base_name = try allocator.dupe(u8, g.base_name),
                    .type_args = new_type_args,
                    .underlying = null,
                } };
            },
            .record => |r| {
                const names_copy = try allocator.alloc([]const u8, r.field_names.len);
                for (r.field_names, 0..) |name, i| {
                    names_copy[i] = try allocator.dupe(u8, name);
                }
                const types_copy = try allocator.alloc(ResolvedType, r.field_types.len);
                for (r.field_types, 0..) |ft, i| {
                    types_copy[i] = try ft.substitute(type_params, type_args, allocator);
                }
                return ResolvedType{ .record = .{
                    .field_names = names_copy,
                    .field_types = types_copy,
                } };
            },
            .union_type => |u| {
                const variants_copy = try allocator.alloc(UnionVariantInfo, u.variants.len);
                for (u.variants, 0..) |v, i| {
                    const names = try allocator.alloc([]const u8, v.field_names.len);
                    for (v.field_names, 0..) |name, j| {
                        names[j] = try allocator.dupe(u8, name);
                    }
                    const types = try allocator.alloc(ResolvedType, v.field_types.len);
                    for (v.field_types, 0..) |ft, j| {
                        types[j] = try ft.substitute(type_params, type_args, allocator);
                    }
                    variants_copy[i] = .{
                        .name = try allocator.dupe(u8, v.name),
                        .field_names = names,
                        .field_types = types,
                    };
                }
                return ResolvedType{ .union_type = .{
                    .variants = variants_copy,
                } };
            },
        };
    }

    /// check if this type contains any unresolved type parameters
    pub fn hasTypeParams(self: ResolvedType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap, .const_value => false,
            .type_param => true,
            .array => |a| a.element_type.hasTypeParams(),
            .vector => |v| v.element_type.hasTypeParams(),
            .view => |v| v.element_type.hasTypeParams(),
            .nullable => |n| n.hasTypeParams(),
            .function_type => |f| {
                for (f.params) |param| {
                    if (param.hasTypeParams()) return true;
                }
                return f.return_type.hasTypeParams();
            },
            .named => |n| n.underlying.hasTypeParams(),
            .result => |r| r.ok_type.hasTypeParams(),
            .range => |r| r.element_type.hasTypeParams(),
            .generic_instance => |g| {
                for (g.type_args) |arg| {
                    if (arg.hasTypeParams()) return true;
                }
                return false;
            },
            .record => |r| {
                for (r.field_types) |ft| {
                    if (ft.hasTypeParams()) return true;
                }
                return false;
            },
            .union_type => |u| {
                for (u.variants) |v| {
                    for (v.field_types) |ft| {
                        if (ft.hasTypeParams()) return true;
                    }
                }
                return false;
            },
        };
    }
};

pub const Effect = enum {
    alloc,
    cpu,
    fs,
    net,
    time,
    rng,
    atomics,
    simd,
    io,
    ffi,

    pub fn fromString(str: []const u8) ?Effect {
        const map = std.StaticStringMap(Effect).initComptime(.{
            .{ "alloc", .alloc },
            .{ "cpu", .cpu },
            .{ "fs", .fs },
            .{ "net", .net },
            .{ "time", .time },
            .{ "rng", .rng },
            .{ "atomics", .atomics },
            .{ "simd", .simd },
            .{ "io", .io },
            .{ "ffi", .ffi },
        });
        return map.get(str);
    }

    pub fn toString(self: Effect) []const u8 {
        return switch (self) {
            .alloc => "alloc",
            .cpu => "cpu",
            .fs => "fs",
            .net => "net",
            .time => "time",
            .rng => "rng",
            .atomics => "atomics",
            .simd => "simd",
            .io => "io",
            .ffi => "ffi",
        };
    }
};
