const std = @import("std");
const types = @import("../types.zig");
const llvm = @import("llvm_bindings.zig");

pub const TypeMapper = struct {
    context: *llvm.ContextRef,
    allocator: std.mem.Allocator,

    pub fn init(context: *llvm.ContextRef, allocator: std.mem.Allocator) TypeMapper {
        return .{
            .context = context,
            .allocator = allocator,
        };
    }

    pub fn mapType(self: *TypeMapper, ferrule_type: types.ResolvedType) !*llvm.TypeRef {
        return switch (ferrule_type) {
            .i8 => llvm.int8Type(self.context),
            .i16 => llvm.int16Type(self.context),
            .i32 => llvm.int32Type(self.context),
            .i64 => llvm.int64Type(self.context),
            .i128 => llvm.int128Type(self.context),
            .u8 => llvm.int8Type(self.context),
            .u16 => llvm.int16Type(self.context),
            .u32 => llvm.int32Type(self.context),
            .u64 => llvm.int64Type(self.context),
            .u128 => llvm.int128Type(self.context),
            .usize_type => llvm.int64Type(self.context),
            .f16 => llvm.halfType(self.context),
            .f32 => llvm.floatType(self.context),
            .f64 => llvm.doubleType(self.context),
            .bool_type => llvm.int1Type(self.context),
            .char_type => llvm.int32Type(self.context),
            .unit_type => llvm.voidType(self.context),

            // string as {ptr, len}
            .string_type => self.createStringType(),

            // bytes as {ptr, len}
            .bytes_type => self.createBytesType(),

            // arrays
            .array => |a| {
                const elem_type = try self.mapType(a.element_type.*);
                if (a.size == 0) {
                    // dynamic array - treat as {ptr, len, cap}
                    return self.createDynamicArrayType(elem_type);
                } else {
                    return llvm.arrayType(elem_type, @intCast(a.size));
                }
            },

            // views as {ptr, len, region_id}
            .view => |v| {
                const elem_type = try self.mapType(v.element_type.*);
                return self.createViewType(elem_type);
            },

            // nullable as {has_value: i1, value: T}
            .nullable => |n| {
                const inner_type = try self.mapType(n.*);
                return self.createNullableType(inner_type);
            },

            // function types
            .function_type => |f| {
                const param_types = try self.allocator.alloc(*llvm.TypeRef, f.params.len);
                defer self.allocator.free(param_types);

                for (f.params, 0..) |param, i| {
                    param_types[i] = try self.mapType(param);
                }

                const return_type = try self.mapType(f.return_type.*);
                return llvm.functionType(return_type, param_types.ptr, @intCast(param_types.len), 0);
            },

            // named types - unwrap to underlying
            .named => |n| try self.mapType(n.underlying.*),

            // result as tagged union {tag: i8, payload: union{ok: T, err: E}}
            .result => |r| {
                const ok_type = try self.mapType(r.ok_type.*);
                return self.createResultType(ok_type);
            },

            // capability types - opaque pointers
            .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => llvm.pointerType(llvm.int8Type(self.context), 0),

            .vector => |v| {
                const elem_type = try self.mapType(v.element_type.*);
                return llvm.vectorType(elem_type, @intCast(v.size));
            },
        };
    }

    fn createStringType(self: *TypeMapper) *llvm.TypeRef {
        const fields = [_]*llvm.TypeRef{
            llvm.pointerType(llvm.int8Type(self.context), 0), // ptr
            llvm.int64Type(self.context), // len
        };
        return llvm.structTypeInContext(self.context, &fields, 2, 0);
    }

    fn createBytesType(self: *TypeMapper) *llvm.TypeRef {
        const fields = [_]*llvm.TypeRef{
            llvm.pointerType(llvm.int8Type(self.context), 0), // ptr
            llvm.int64Type(self.context), // len
        };
        return llvm.structTypeInContext(self.context, &fields, 2, 0);
    }

    fn createViewType(self: *TypeMapper, element_type: *llvm.TypeRef) *llvm.TypeRef {
        const fields = [_]*llvm.TypeRef{
            llvm.pointerType(element_type, 0), // ptr
            llvm.int64Type(self.context), // len
            llvm.int32Type(self.context), // region_id
        };
        return llvm.structTypeInContext(self.context, &fields, 3, 0);
    }

    fn createDynamicArrayType(self: *TypeMapper, element_type: *llvm.TypeRef) *llvm.TypeRef {
        const fields = [_]*llvm.TypeRef{
            llvm.pointerType(element_type, 0), // ptr
            llvm.int64Type(self.context), // len
            llvm.int64Type(self.context), // cap
        };
        return llvm.structTypeInContext(self.context, &fields, 3, 0);
    }

    fn createNullableType(self: *TypeMapper, inner_type: *llvm.TypeRef) *llvm.TypeRef {
        const fields = [_]*llvm.TypeRef{
            llvm.int1Type(self.context), // has_value
            inner_type, // value
        };
        return llvm.structTypeInContext(self.context, &fields, 2, 0);
    }

    fn createResultType(self: *TypeMapper, ok_type: *llvm.TypeRef) *llvm.TypeRef {
        // simplified: {tag: i8, ok_value: T}
        // full version would need union for error payload
        const fields = [_]*llvm.TypeRef{
            llvm.int8Type(self.context), // tag: 0 = ok, 1 = err
            ok_type, // payload (ok value)
            llvm.int64Type(self.context), // error code (simplified)
        };
        return llvm.structTypeInContext(self.context, &fields, 3, 0);
    }
};
