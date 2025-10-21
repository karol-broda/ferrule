const std = @import("std");

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
    },

    named: struct {
        name: []const u8,
        underlying: *ResolvedType,
    },

    result: struct {
        ok_type: *ResolvedType,
        error_domain: []const u8,
    },

    pub fn clone(self: ResolvedType, allocator: std.mem.Allocator) std.mem.Allocator.Error!ResolvedType {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => self,
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
                return ResolvedType{ .function_type = .{
                    .params = params_copy,
                    .return_type = ret_ptr,
                    .effects = effects_copy,
                    .error_domain = domain_copy,
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
        };
    }

    pub fn deinit(self: *const ResolvedType, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => {},
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
        }
    }

    pub fn eql(self: *const ResolvedType, other: *const ResolvedType) bool {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) {
            return false;
        }

        return switch (self.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => true,
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
        }
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
