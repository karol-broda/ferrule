//! compilation context module - arena-based memory management for the ferrule compiler
//!
//! this module provides centralized memory management using arena allocators and
//! interning tables, eliminating the need for manual per-item cleanup and solving
//! ownership ambiguity issues in the codebase.
//!
//! key components:
//! - `CompilationContext`: central struct that manages all memory for a compilation unit
//! - `StringInterner`: deduplicates strings across the compilation
//! - `TypeInterner`: deduplicates resolved types across the compilation
//!
//! memory arenas:
//! - `permanent_arena`: for data that lives the entire compilation
//!   - interned types and strings
//!   - symbol table entries
//!   - diagnostics
//!   - use: ctx.permanentAllocator()
//!
//! - `scratch_arena`: for temporary per-phase allocations
//!   - AST nodes (freed after semantic analysis)
//!   - temporary buffers during parsing
//!   - use: ctx.scratchAllocator()
//!   - call ctx.resetScratch() between phases to reclaim memory
//!
//! usage:
//!   var ctx = CompilationContext.init(allocator);
//!   defer ctx.deinit();  // frees everything at once
//!
//!   // parsing phase - use scratch for AST
//!   const ast_alloc = ctx.scratchAllocator();
//!   var parser = Parser.init(ast_alloc, tokens);
//!   const module = try parser.parse();
//!
//!   // semantic analysis - uses permanent for types
//!   var analyzer = SemanticAnalyzer.init(&ctx, source_file, source);
//!   const result = try analyzer.analyze(module);
//!
//!   // optional: free AST after semantic analysis
//!   // ctx.resetScratch();
//!
//!   // interning for deduplication
//!   const name = try ctx.internString("foo");  // stable for ctx lifetime
//!   const t = try ctx.internType(.i32);        // same type = same pointer
//!
//! benefits:
//! - no manual deinit functions needed in ast.zig when using scratch arena
//! - no ResolvedType.clone() or ResolvedType.deinit() needed for interned types
//! - no double-free bugs from shared type ownership
//! - reduced memory usage through deduplication
//! - simplified cleanup: one ctx.deinit() frees everything

const std = @import("std");
const types = @import("types.zig");

// string interner for deduplicating strings across the compilation
// all interned strings are stable for the lifetime of the compilation context
pub const StringInterner = struct {
    arena: std.mem.Allocator,
    // maps string content to the canonical interned slice
    strings: std.StringHashMap([]const u8),

    pub fn init(arena: std.mem.Allocator) StringInterner {
        return .{
            .arena = arena,
            .strings = std.StringHashMap([]const u8).init(arena),
        };
    }

    // interns a string, returning a stable slice that lives for the compilation lifetime
    // if the string was already interned, returns the existing slice (pointer equality)
    pub fn intern(self: *StringInterner, str: []const u8) std.mem.Allocator.Error![]const u8 {
        if (self.strings.get(str)) |existing| {
            return existing;
        }

        // allocate a copy in the arena
        const owned = try self.arena.dupe(u8, str);
        try self.strings.put(owned, owned);
        return owned;
    }

    // checks if a string is already interned without interning it
    pub fn get(self: *const StringInterner, str: []const u8) ?[]const u8 {
        return self.strings.get(str);
    }

    // no deinit needed - arena owns all memory
};

// type interner for deduplicating resolved types across the compilation
// all interned types are stable for the lifetime of the compilation context
pub const TypeInterner = struct {
    arena: std.mem.Allocator,
    // pointer to heap-allocated string interner (allocated in permanent arena)
    string_interner: *StringInterner,

    // stores all interned types in an array with linear scan for matching
    // this approach handles hash collisions and works well for typical program sizes
    interned_types: std.ArrayList(*const types.ResolvedType),

    // primitive type singletons - allocated once and reused
    i8_type: ?*const types.ResolvedType,
    i16_type: ?*const types.ResolvedType,
    i32_type: ?*const types.ResolvedType,
    i64_type: ?*const types.ResolvedType,
    i128_type: ?*const types.ResolvedType,
    u8_type: ?*const types.ResolvedType,
    u16_type: ?*const types.ResolvedType,
    u32_type: ?*const types.ResolvedType,
    u64_type: ?*const types.ResolvedType,
    u128_type: ?*const types.ResolvedType,
    usize_type: ?*const types.ResolvedType,
    f16_type: ?*const types.ResolvedType,
    f32_type: ?*const types.ResolvedType,
    f64_type: ?*const types.ResolvedType,
    bool_type: ?*const types.ResolvedType,
    char_type: ?*const types.ResolvedType,
    string_type: ?*const types.ResolvedType,
    bytes_type: ?*const types.ResolvedType,
    unit_type: ?*const types.ResolvedType,

    // capability type singletons
    fs_cap: ?*const types.ResolvedType,
    net_cap: ?*const types.ResolvedType,
    io_cap: ?*const types.ResolvedType,
    time_cap: ?*const types.ResolvedType,
    rng_cap: ?*const types.ResolvedType,
    alloc_cap: ?*const types.ResolvedType,
    cpu_cap: ?*const types.ResolvedType,
    atomics_cap: ?*const types.ResolvedType,
    simd_cap: ?*const types.ResolvedType,
    ffi_cap: ?*const types.ResolvedType,

    pub fn init(arena: std.mem.Allocator, string_interner: *StringInterner) TypeInterner {
        return .{
            .arena = arena,
            .string_interner = string_interner,
            .interned_types = std.ArrayList(*const types.ResolvedType){},
            .i8_type = null,
            .i16_type = null,
            .i32_type = null,
            .i64_type = null,
            .i128_type = null,
            .u8_type = null,
            .u16_type = null,
            .u32_type = null,
            .u64_type = null,
            .u128_type = null,
            .usize_type = null,
            .f16_type = null,
            .f32_type = null,
            .f64_type = null,
            .bool_type = null,
            .char_type = null,
            .string_type = null,
            .bytes_type = null,
            .unit_type = null,
            .fs_cap = null,
            .net_cap = null,
            .io_cap = null,
            .time_cap = null,
            .rng_cap = null,
            .alloc_cap = null,
            .cpu_cap = null,
            .atomics_cap = null,
            .simd_cap = null,
            .ffi_cap = null,
        };
    }

    // interns a resolved type, returning a stable pointer that lives for the compilation lifetime
    // if an equivalent type was already interned, returns the existing pointer
    pub fn intern(self: *TypeInterner, resolved_type: types.ResolvedType) std.mem.Allocator.Error!*const types.ResolvedType {
        // fast path for primitive types - use cached singletons
        switch (resolved_type) {
            .i8 => return self.getPrimitive(&self.i8_type, .i8),
            .i16 => return self.getPrimitive(&self.i16_type, .i16),
            .i32 => return self.getPrimitive(&self.i32_type, .i32),
            .i64 => return self.getPrimitive(&self.i64_type, .i64),
            .i128 => return self.getPrimitive(&self.i128_type, .i128),
            .u8 => return self.getPrimitive(&self.u8_type, .u8),
            .u16 => return self.getPrimitive(&self.u16_type, .u16),
            .u32 => return self.getPrimitive(&self.u32_type, .u32),
            .u64 => return self.getPrimitive(&self.u64_type, .u64),
            .u128 => return self.getPrimitive(&self.u128_type, .u128),
            .usize_type => return self.getPrimitive(&self.usize_type, .usize_type),
            .f16 => return self.getPrimitive(&self.f16_type, .f16),
            .f32 => return self.getPrimitive(&self.f32_type, .f32),
            .f64 => return self.getPrimitive(&self.f64_type, .f64),
            .bool_type => return self.getPrimitive(&self.bool_type, .bool_type),
            .char_type => return self.getPrimitive(&self.char_type, .char_type),
            .string_type => return self.getPrimitive(&self.string_type, .string_type),
            .bytes_type => return self.getPrimitive(&self.bytes_type, .bytes_type),
            .unit_type => return self.getPrimitive(&self.unit_type, .unit_type),
            .fs_cap => return self.getPrimitive(&self.fs_cap, .fs_cap),
            .net_cap => return self.getPrimitive(&self.net_cap, .net_cap),
            .io_cap => return self.getPrimitive(&self.io_cap, .io_cap),
            .time_cap => return self.getPrimitive(&self.time_cap, .time_cap),
            .rng_cap => return self.getPrimitive(&self.rng_cap, .rng_cap),
            .alloc_cap => return self.getPrimitive(&self.alloc_cap, .alloc_cap),
            .cpu_cap => return self.getPrimitive(&self.cpu_cap, .cpu_cap),
            .atomics_cap => return self.getPrimitive(&self.atomics_cap, .atomics_cap),
            .simd_cap => return self.getPrimitive(&self.simd_cap, .simd_cap),
            .ffi_cap => return self.getPrimitive(&self.ffi_cap, .ffi_cap),
            else => {},
        }

        // check if an equivalent type already exists
        for (self.interned_types.items) |existing| {
            if (existing.eql(&resolved_type)) {
                return existing;
            }
        }

        // allocate new type in arena and copy the structure deeply
        const new_type = try self.allocateType(resolved_type);
        try self.interned_types.append(self.arena, new_type);
        return new_type;
    }

    fn getPrimitive(self: *TypeInterner, cache: *?*const types.ResolvedType, value: types.ResolvedType) std.mem.Allocator.Error!*const types.ResolvedType {
        if (cache.*) |cached| {
            return cached;
        }
        const ptr = try self.arena.create(types.ResolvedType);
        ptr.* = value;
        cache.* = ptr;
        return ptr;
    }

    // allocates a deep copy of a type in the arena, interning all nested strings and types
    fn allocateType(self: *TypeInterner, resolved_type: types.ResolvedType) std.mem.Allocator.Error!*const types.ResolvedType {
        const ptr = try self.arena.create(types.ResolvedType);
        ptr.* = try self.deepCopyType(resolved_type);
        return ptr;
    }

    fn deepCopyType(self: *TypeInterner, resolved_type: types.ResolvedType) std.mem.Allocator.Error!types.ResolvedType {
        return switch (resolved_type) {
            // primitives and capabilities - return as-is
            .i8, .i16, .i32, .i64, .i128, .u8, .u16, .u32, .u64, .u128, .usize_type, .f16, .f32, .f64, .bool_type, .char_type, .string_type, .bytes_type, .unit_type, .fs_cap, .net_cap, .io_cap, .time_cap, .rng_cap, .alloc_cap, .cpu_cap, .atomics_cap, .simd_cap, .ffi_cap => resolved_type,

            .type_param => |tp| types.ResolvedType{
                .type_param = .{
                    .name = try self.string_interner.intern(tp.name),
                    .index = tp.index,
                },
            },

            .array => |a| blk: {
                const elem_ptr = try self.arena.create(types.ResolvedType);
                elem_ptr.* = try self.deepCopyType(a.element_type.*);
                break :blk types.ResolvedType{ .array = .{
                    .element_type = elem_ptr,
                    .size = a.size,
                } };
            },

            .vector => |v| blk: {
                const elem_ptr = try self.arena.create(types.ResolvedType);
                elem_ptr.* = try self.deepCopyType(v.element_type.*);
                break :blk types.ResolvedType{ .vector = .{
                    .element_type = elem_ptr,
                    .size = v.size,
                } };
            },

            .view => |v| blk: {
                const elem_ptr = try self.arena.create(types.ResolvedType);
                elem_ptr.* = try self.deepCopyType(v.element_type.*);
                break :blk types.ResolvedType{ .view = .{
                    .element_type = elem_ptr,
                    .mutable = v.mutable,
                } };
            },

            .nullable => |n| blk: {
                const inner_ptr = try self.arena.create(types.ResolvedType);
                inner_ptr.* = try self.deepCopyType(n.*);
                break :blk types.ResolvedType{ .nullable = inner_ptr };
            },

            .function_type => |f| blk: {
                const params_copy = try self.arena.alloc(types.ResolvedType, f.params.len);
                for (f.params, 0..) |param, i| {
                    params_copy[i] = try self.deepCopyType(param);
                }

                const ret_ptr = try self.arena.create(types.ResolvedType);
                ret_ptr.* = try self.deepCopyType(f.return_type.*);

                const effects_copy = try self.arena.dupe(types.Effect, f.effects);

                const domain_copy: ?[]const u8 = if (f.error_domain) |domain|
                    try self.string_interner.intern(domain)
                else
                    null;

                const type_params_copy: ?[]types.TypeParamInfo = if (f.type_params) |tps| inner: {
                    const copy = try self.arena.alloc(types.TypeParamInfo, tps.len);
                    for (tps, 0..) |tp, i| {
                        copy[i] = .{
                            .name = try self.string_interner.intern(tp.name),
                            .variance = tp.variance,
                            .constraint = if (tp.constraint) |c| constraint: {
                                const c_ptr = try self.arena.create(types.ResolvedType);
                                c_ptr.* = try self.deepCopyType(c.*);
                                break :constraint c_ptr;
                            } else null,
                            .is_const = tp.is_const,
                            .const_type = if (tp.const_type) |ct| const_t: {
                                const ct_ptr = try self.arena.create(types.ResolvedType);
                                ct_ptr.* = try self.deepCopyType(ct.*);
                                break :const_t ct_ptr;
                            } else null,
                        };
                    }
                    break :inner copy;
                } else null;

                break :blk types.ResolvedType{ .function_type = .{
                    .params = params_copy,
                    .return_type = ret_ptr,
                    .effects = effects_copy,
                    .error_domain = domain_copy,
                    .type_params = type_params_copy,
                } };
            },

            .named => |n| blk: {
                const under_ptr = try self.arena.create(types.ResolvedType);
                under_ptr.* = try self.deepCopyType(n.underlying.*);
                break :blk types.ResolvedType{ .named = .{
                    .name = try self.string_interner.intern(n.name),
                    .underlying = under_ptr,
                } };
            },

            .result => |r| blk: {
                const ok_ptr = try self.arena.create(types.ResolvedType);
                ok_ptr.* = try self.deepCopyType(r.ok_type.*);
                break :blk types.ResolvedType{ .result = .{
                    .ok_type = ok_ptr,
                    .error_domain = try self.string_interner.intern(r.error_domain),
                } };
            },

            .range => |r| blk: {
                const elem_ptr = try self.arena.create(types.ResolvedType);
                elem_ptr.* = try self.deepCopyType(r.element_type.*);
                break :blk types.ResolvedType{ .range = .{
                    .element_type = elem_ptr,
                } };
            },

            .generic_instance => |g| blk: {
                const type_args_copy = try self.arena.alloc(types.ResolvedType, g.type_args.len);
                for (g.type_args, 0..) |arg, i| {
                    type_args_copy[i] = try self.deepCopyType(arg);
                }

                const underlying_copy: ?*types.ResolvedType = if (g.underlying) |u| inner: {
                    const u_ptr = try self.arena.create(types.ResolvedType);
                    u_ptr.* = try self.deepCopyType(u.*);
                    break :inner u_ptr;
                } else null;

                break :blk types.ResolvedType{ .generic_instance = .{
                    .base_name = try self.string_interner.intern(g.base_name),
                    .type_args = type_args_copy,
                    .underlying = underlying_copy,
                } };
            },

            .const_value => |cv| blk: {
                const ct_ptr = try self.arena.create(types.ResolvedType);
                ct_ptr.* = try self.deepCopyType(cv.const_type.*);
                break :blk types.ResolvedType{ .const_value = .{
                    .value = cv.value,
                    .const_type = ct_ptr,
                } };
            },

            .record => |r| blk: {
                const names_copy = try self.arena.alloc([]const u8, r.field_names.len);
                for (r.field_names, 0..) |name, i| {
                    names_copy[i] = try self.string_interner.intern(name);
                }

                const types_copy = try self.arena.alloc(types.ResolvedType, r.field_types.len);
                for (r.field_types, 0..) |ft, i| {
                    types_copy[i] = try self.deepCopyType(ft);
                }

                const locs_copy: ?[]const types.FieldLocation = if (r.field_locations) |locs|
                    try self.arena.dupe(types.FieldLocation, locs)
                else
                    null;

                break :blk types.ResolvedType{ .record = .{
                    .field_names = names_copy,
                    .field_types = types_copy,
                    .field_locations = locs_copy,
                } };
            },

            .union_type => |u| blk: {
                const variants_copy = try self.arena.alloc(types.UnionVariantInfo, u.variants.len);
                for (u.variants, 0..) |v, i| {
                    const names = try self.arena.alloc([]const u8, v.field_names.len);
                    for (v.field_names, 0..) |name, j| {
                        names[j] = try self.string_interner.intern(name);
                    }

                    const field_types = try self.arena.alloc(types.ResolvedType, v.field_types.len);
                    for (v.field_types, 0..) |ft, j| {
                        field_types[j] = try self.deepCopyType(ft);
                    }

                    variants_copy[i] = .{
                        .name = try self.string_interner.intern(v.name),
                        .field_names = names,
                        .field_types = field_types,
                    };
                }

                break :blk types.ResolvedType{ .union_type = .{
                    .variants = variants_copy,
                } };
            },
        };
    }

    // no deinit needed - arena owns all memory
};

// compilation context that manages memory for an entire compilation unit
// provides arena allocators for different lifetime scopes and interning tables
pub const CompilationContext = struct {
    // backing allocator used for arena backing storage
    backing_allocator: std.mem.Allocator,

    // permanent arena for data that lives the entire compilation
    // (interned types, interned strings, symbol table entries, diagnostics)
    // heap-allocated to ensure stable pointer when struct is moved
    permanent_arena: *std.heap.ArenaAllocator,

    // scratch arena for temporary per-phase allocations that can be reset between phases
    // heap-allocated to ensure stable pointer when struct is moved
    scratch_arena: *std.heap.ArenaAllocator,

    // interners for deduplication - string_interner is heap-allocated to ensure
    // stable pointer that type_interner can reference
    string_interner: *StringInterner,
    type_interner: TypeInterner,

    pub fn init(backing_allocator: std.mem.Allocator) CompilationContext {
        // allocate arenas on heap so their addresses are stable even when
        // the CompilationContext struct is moved/copied
        const permanent_arena_ptr = backing_allocator.create(std.heap.ArenaAllocator) catch unreachable;
        permanent_arena_ptr.* = std.heap.ArenaAllocator.init(backing_allocator);

        const scratch_arena_ptr = backing_allocator.create(std.heap.ArenaAllocator) catch unreachable;
        scratch_arena_ptr.* = std.heap.ArenaAllocator.init(backing_allocator);

        const permanent_alloc = permanent_arena_ptr.allocator();

        // allocate string_interner on the heap so its address is stable
        const string_interner_ptr = permanent_alloc.create(StringInterner) catch unreachable;
        string_interner_ptr.* = StringInterner.init(permanent_alloc);

        return CompilationContext{
            .backing_allocator = backing_allocator,
            .permanent_arena = permanent_arena_ptr,
            .scratch_arena = scratch_arena_ptr,
            .string_interner = string_interner_ptr,
            .type_interner = TypeInterner.init(permanent_alloc, string_interner_ptr),
        };
    }

    // returns the permanent allocator for long-lived data
    pub fn permanentAllocator(self: *CompilationContext) std.mem.Allocator {
        return self.permanent_arena.allocator();
    }

    // returns the scratch allocator for temporary data
    pub fn scratchAllocator(self: *CompilationContext) std.mem.Allocator {
        return self.scratch_arena.allocator();
    }

    // resets the scratch arena, freeing all temporary allocations
    // call this between compilation phases to reclaim memory
    pub fn resetScratch(self: *CompilationContext) void {
        _ = self.scratch_arena.reset(.retain_capacity);
    }

    // interns a string in the permanent arena
    pub fn internString(self: *CompilationContext, str: []const u8) std.mem.Allocator.Error![]const u8 {
        return self.string_interner.intern(str);
    }

    // interns a type in the permanent arena
    pub fn internType(self: *CompilationContext, resolved_type: types.ResolvedType) std.mem.Allocator.Error!*const types.ResolvedType {
        return self.type_interner.intern(resolved_type);
    }

    // frees all memory - call when compilation is complete
    pub fn deinit(self: *CompilationContext) void {
        // scratch arena is freed first
        self.scratch_arena.deinit();
        self.backing_allocator.destroy(self.scratch_arena);
        // permanent arena frees all interned data (including string_interner)
        self.permanent_arena.deinit();
        self.backing_allocator.destroy(self.permanent_arena);
    }
};

// tests
test "string interner deduplicates strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var interner = StringInterner.init(arena.allocator());

    const s1 = try interner.intern("hello");
    const s2 = try interner.intern("hello");
    const s3 = try interner.intern("world");

    // same string should return same pointer
    try std.testing.expectEqual(s1.ptr, s2.ptr);
    // different string should return different pointer
    try std.testing.expect(s1.ptr != s3.ptr);
    // content should be equal
    try std.testing.expectEqualStrings("hello", s1);
    try std.testing.expectEqualStrings("world", s3);
}

test "type interner deduplicates primitive types" {
    var ctx = CompilationContext.init(std.testing.allocator);
    defer ctx.deinit();

    const t1 = try ctx.internType(.i32);
    const t2 = try ctx.internType(.i32);
    const t3 = try ctx.internType(.string_type);

    // same type should return same pointer
    try std.testing.expectEqual(t1, t2);
    // different type should return different pointer
    try std.testing.expect(t1 != t3);
}

test "compilation context basic usage" {
    var ctx = CompilationContext.init(std.testing.allocator);
    defer ctx.deinit();

    // intern some strings
    const name1 = try ctx.internString("foo");
    const name2 = try ctx.internString("foo");
    try std.testing.expectEqual(name1.ptr, name2.ptr);

    // use scratch allocator
    const scratch = ctx.scratchAllocator();
    const temp = try scratch.alloc(u8, 100);
    _ = temp;

    // reset scratch
    ctx.resetScratch();

    // permanent data should still be valid
    try std.testing.expectEqualStrings("foo", name1);
}
