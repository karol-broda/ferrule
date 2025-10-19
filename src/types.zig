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

    pub fn eql(self: *const ResolvedType, other: *const ResolvedType) bool {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) {
            return false;
        }

        return switch (self.*) {
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type => true,
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
            .array => |a| try writer.print("[{d}]{any}", .{ a.size, a.element_type.* }),
            .vector => |v| try writer.print("<{d}>{any}", .{ v.size, v.element_type.* }),
            .view => |v| {
                if (v.mutable) {
                    try writer.print("&mut {any}", .{v.element_type.*});
                } else {
                    try writer.print("&{any}", .{v.element_type.*});
                }
            },
            .nullable => |n| try writer.print("?{any}", .{n.*}),
            .function_type => |f| {
                try writer.writeAll("(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{any}", .{p});
                }
                try writer.print(") -> {any}", .{f.return_type.*});
            },
            .named => |n| try writer.writeAll(n.name),
            .result => |r| try writer.print("Result<{any}, {s}>", .{ r.ok_type.*, r.error_domain }),
        }
    }

    pub fn deinit(self: *const ResolvedType, allocator: std.mem.Allocator) void {
        switch (self.*) {
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
                for (f.params) |*p| {
                    p.deinit(allocator);
                }
                allocator.free(f.params);
                f.return_type.deinit(allocator);
                allocator.destroy(f.return_type);
                allocator.free(f.effects);
            },
            .named => |n| {
                n.underlying.deinit(allocator);
                allocator.destroy(n.underlying);
            },
            .result => |r| {
                r.ok_type.deinit(allocator);
                allocator.destroy(r.ok_type);
            },
            else => {},
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
