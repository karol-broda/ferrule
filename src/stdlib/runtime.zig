//! ferrule runtime library - provides runtime functions called by generated code
//! build as static library (libferrule_rt.a) and link with ferrule programs

const std = @import("std");
const posix = std.posix;

// ============================================================================
// error context frames
// ============================================================================

/// maximum number of frames in a context chain
const MAX_FRAMES: usize = 32;

/// maximum key/value pairs per frame
const MAX_FRAME_FIELDS: usize = 8;

/// maximum length of a key or string value
const MAX_FIELD_LEN: usize = 128;

/// a single key-value pair in a context frame
pub const FrameField = extern struct {
    key_ptr: [*]const u8,
    key_len: usize,
    value_ptr: [*]const u8,
    value_len: usize,
    value_type: FrameValueType,
};

/// type of value stored in a frame field
pub const FrameValueType = enum(u8) {
    string = 0,
    i64 = 1,
    u64 = 2,
    bool = 3,
};

/// a context frame containing key-value pairs for error debugging
pub const ErrorFrame = extern struct {
    fields: [MAX_FRAME_FIELDS]FrameField,
    field_count: usize,
    next: ?*ErrorFrame,
};

/// thread-local frame allocator (simple bump allocator with fixed pool)
var frame_pool: [MAX_FRAMES]ErrorFrame = undefined;
var frame_pool_index: usize = 0;

/// allocate a new error frame from the pool
export fn rt_frame_alloc() ?*ErrorFrame {
    if (frame_pool_index >= MAX_FRAMES) {
        return null;
    }
    const frame = &frame_pool[frame_pool_index];
    frame_pool_index += 1;
    frame.field_count = 0;
    frame.next = null;
    return frame;
}

/// reset the frame pool (call at error boundary / function return)
export fn rt_frame_pool_reset() void {
    frame_pool_index = 0;
}

/// add a string field to a frame
export fn rt_frame_add_string(
    frame: *ErrorFrame,
    key_ptr: [*]const u8,
    key_len: usize,
    value_ptr: [*]const u8,
    value_len: usize,
) bool {
    if (frame.field_count >= MAX_FRAME_FIELDS) {
        return false;
    }
    frame.fields[frame.field_count] = .{
        .key_ptr = key_ptr,
        .key_len = key_len,
        .value_ptr = value_ptr,
        .value_len = value_len,
        .value_type = .string,
    };
    frame.field_count += 1;
    return true;
}

/// add an i64 field to a frame (value stored as string representation)
export fn rt_frame_add_i64(
    frame: *ErrorFrame,
    key_ptr: [*]const u8,
    key_len: usize,
    value: i64,
) bool {
    if (frame.field_count >= MAX_FRAME_FIELDS) {
        return false;
    }
    // store the i64 value directly - we'll format it on print
    // for simplicity, store the bytes of the i64
    frame.fields[frame.field_count] = .{
        .key_ptr = key_ptr,
        .key_len = key_len,
        .value_ptr = @ptrCast(&value),
        .value_len = @sizeOf(i64),
        .value_type = .i64,
    };
    frame.field_count += 1;
    return true;
}

/// chain a frame to another (for nested context)
export fn rt_frame_chain(frame: *ErrorFrame, parent: *ErrorFrame) void {
    frame.next = parent;
}

/// print error frames to stderr for debugging
export fn rt_frame_print(frame: ?*const ErrorFrame) void {
    var current = frame;
    var depth: usize = 0;

    while (current) |f| : (depth += 1) {
        if (depth > MAX_FRAMES) break; // safety limit

        rt_eprint("  context[", 10);
        var depth_buf: [8]u8 = undefined;
        const depth_str = std.fmt.bufPrint(&depth_buf, "{d}", .{depth}) catch "?";
        rt_eprint(depth_str.ptr, depth_str.len);
        rt_eprintln("]:", 2);

        var i: usize = 0;
        while (i < f.field_count) : (i += 1) {
            const field = &f.fields[i];
            rt_eprint("    ", 4);
            rt_eprint(field.key_ptr, field.key_len);
            rt_eprint(": ", 2);

            switch (field.value_type) {
                .string => {
                    rt_eprint(field.value_ptr, field.value_len);
                },
                .i64 => {
                    const val = @as(*const i64, @ptrCast(@alignCast(field.value_ptr))).*;
                    var buf: [24]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch "?";
                    rt_eprint(str.ptr, str.len);
                },
                .u64 => {
                    const val = @as(*const u64, @ptrCast(@alignCast(field.value_ptr))).*;
                    var buf: [24]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch "?";
                    rt_eprint(str.ptr, str.len);
                },
                .bool => {
                    const val = @as(*const bool, @ptrCast(field.value_ptr)).*;
                    const str = if (val) "true" else "false";
                    rt_eprint(str.ptr, str.len);
                },
            }
            rt_eprint("\n", 1);
        }

        current = f.next;
    }
}

// ============================================================================
// result type helpers
// ============================================================================

/// result tag values
pub const RESULT_OK: u8 = 0;
pub const RESULT_ERR: u8 = 1;

/// generic result header - actual result structs follow this pattern:
/// struct { tag: u8, padding: [7]u8, value_or_error: T, frame: ?*ErrorFrame }
/// the value_or_error union is type-specific
/// print an error with its context frames
export fn rt_error_print(
    domain_ptr: [*]const u8,
    domain_len: usize,
    variant_ptr: [*]const u8,
    variant_len: usize,
    frame: ?*const ErrorFrame,
) void {
    rt_eprint("error: ", 7);
    rt_eprint(domain_ptr, domain_len);
    rt_eprint(".", 1);
    rt_eprintln(variant_ptr, variant_len);

    if (frame != null) {
        rt_frame_print(frame);
    }
}

fn getStdout() std.fs.File {
    return std.fs.File.stdout();
}

fn getStderr() std.fs.File {
    return std.fs.File.stderr();
}

fn getStdin() std.fs.File {
    return std.fs.File.stdin();
}

// stdout

export fn rt_print(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    getStdout().writeAll(str) catch {};
}

export fn rt_println(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    const stdout = getStdout();
    stdout.writeAll(str) catch {};
    stdout.writeAll("\n") catch {};
}

export fn rt_print_i8(value: i8) void {
    var buf: [8]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_i32(value: i32) void {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_i64(value: i64) void {
    var buf: [24]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_u64(value: u64) void {
    var buf: [24]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_f32(value: f32) void {
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_f64(value: f64) void {
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    getStdout().writeAll(result) catch {};
}

export fn rt_print_bool(value: bool) void {
    const str = if (value) "true" else "false";
    getStdout().writeAll(str) catch {};
}

export fn rt_print_newline() void {
    getStdout().writeAll("\n") catch {};
}

// result type printing
// prints a result in format: "ok: <value>" or "err: <error_code>"
export fn rt_print_result_i32(tag: i8, value: i32, error_code: i64) void {
    const stdout = getStdout();
    if (tag == 0) {
        stdout.writeAll("ok: ") catch {};
        var buf: [20]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        stdout.writeAll(result) catch {};
    } else {
        stdout.writeAll("err: 0x") catch {};
        var buf: [16]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(error_code))}) catch return;
        stdout.writeAll(result) catch {};
    }
}

export fn rt_print_result_i64(tag: i8, value: i64, error_code: i64) void {
    const stdout = getStdout();
    if (tag == 0) {
        stdout.writeAll("ok: ") catch {};
        var buf: [24]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        stdout.writeAll(result) catch {};
    } else {
        stdout.writeAll("err: 0x") catch {};
        var buf: [16]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(error_code))}) catch return;
        stdout.writeAll(result) catch {};
    }
}

export fn rt_print_result_f64(tag: i8, value: f64, error_code: i64) void {
    const stdout = getStdout();
    if (tag == 0) {
        stdout.writeAll("ok: ") catch {};
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        stdout.writeAll(result) catch {};
    } else {
        stdout.writeAll("err: 0x") catch {};
        var buf: [16]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(error_code))}) catch return;
        stdout.writeAll(result) catch {};
    }
}

export fn rt_print_result_bool(tag: i8, value: bool, error_code: i64) void {
    const stdout = getStdout();
    if (tag == 0) {
        stdout.writeAll("ok: ") catch {};
        const str = if (value) "true" else "false";
        stdout.writeAll(str) catch {};
    } else {
        stdout.writeAll("err: 0x") catch {};
        var buf: [16]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(error_code))}) catch return;
        stdout.writeAll(result) catch {};
    }
}

// debug print with newline - useful for quick debugging
export fn rt_dbg_i32(label_ptr: [*]const u8, label_len: usize, value: i32) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = ") catch {};
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    stdout.writeAll(result) catch {};
    stdout.writeAll("\n") catch {};
}

export fn rt_dbg_i64(label_ptr: [*]const u8, label_len: usize, value: i64) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = ") catch {};
    var buf: [24]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    stdout.writeAll(result) catch {};
    stdout.writeAll("\n") catch {};
}

export fn rt_dbg_f64(label_ptr: [*]const u8, label_len: usize, value: f64) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = ") catch {};
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    stdout.writeAll(result) catch {};
    stdout.writeAll("\n") catch {};
}

export fn rt_dbg_bool(label_ptr: [*]const u8, label_len: usize, value: bool) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = ") catch {};
    const str = if (value) "true" else "false";
    stdout.writeAll(str) catch {};
    stdout.writeAll("\n") catch {};
}

export fn rt_dbg_str(label_ptr: [*]const u8, label_len: usize, str_ptr: [*]const u8, str_len: usize) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = \"") catch {};
    stdout.writeAll(str_ptr[0..str_len]) catch {};
    stdout.writeAll("\"\n") catch {};
}

export fn rt_dbg_result_i32(label_ptr: [*]const u8, label_len: usize, tag: i8, value: i32, error_code: i64) void {
    const stdout = getStdout();
    stdout.writeAll(label_ptr[0..label_len]) catch {};
    stdout.writeAll(" = ") catch {};
    rt_print_result_i32(tag, value, error_code);
    stdout.writeAll("\n") catch {};
}

// convert i32 to string and return length
export fn rt_i32_len(value: i32) usize {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return 0;
    return result.len;
}

// stderr

export fn rt_eprint(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    getStderr().writeAll(str) catch {};
}

export fn rt_eprintln(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    const stderr_file = getStderr();
    stderr_file.writeAll(str) catch {};
    stderr_file.writeAll("\n") catch {};
}

// stdin

export fn rt_read_line(buf_ptr: [*]u8, buf_len: usize) i64 {
    const buf = buf_ptr[0..buf_len];
    const stdin = getStdin();

    var i: usize = 0;
    while (i < buf.len) {
        var byte_buf: [1]u8 = undefined;
        const bytes_read = stdin.read(&byte_buf) catch return -1;

        if (bytes_read == 0) {
            if (i == 0) return -1;
            return @intCast(i);
        }

        const byte = byte_buf[0];
        if (byte == '\n') {
            return @intCast(i);
        }

        buf[i] = byte;
        i += 1;
    }

    return @intCast(i);
}

export fn rt_read_char() i32 {
    const stdin = getStdin();
    var byte_buf: [1]u8 = undefined;
    const bytes_read = stdin.read(&byte_buf) catch return -1;
    if (bytes_read == 0) return -1;
    return @intCast(byte_buf[0]);
}

// string operations

export fn rt_string_alloc(len: usize) ?[*]u8 {
    const slice = std.heap.c_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

export fn rt_string_free(ptr: [*]u8, len: usize) void {
    std.heap.c_allocator.free(ptr[0..len]);
}

export fn rt_string_concat(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) bool {
    const total_len = a_len + b_len;
    const result = std.heap.c_allocator.alloc(u8, total_len) catch return false;
    @memcpy(result[0..a_len], a_ptr[0..a_len]);
    @memcpy(result[a_len..], b_ptr[0..b_len]);
    out_ptr.* = result.ptr;
    out_len.* = total_len;
    return true;
}

export fn rt_string_eq(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
) bool {
    if (a_len != b_len) return false;
    return std.mem.eql(u8, a_ptr[0..a_len], b_ptr[0..b_len]);
}

export fn rt_cstr_len(ptr: [*:0]const u8) usize {
    return std.mem.len(ptr);
}

// parsing

export fn rt_parse_i32(str_ptr: [*]const u8, str_len: usize) i32 {
    const str = str_ptr[0..str_len];
    return std.fmt.parseInt(i32, str, 10) catch 0;
}

export fn rt_parse_i64(str_ptr: [*]const u8, str_len: usize) i64 {
    const str = str_ptr[0..str_len];
    return std.fmt.parseInt(i64, str, 10) catch 0;
}

export fn rt_parse_f64(str_ptr: [*]const u8, str_len: usize) f64 {
    const str = str_ptr[0..str_len];
    return std.fmt.parseFloat(f64, str) catch 0.0;
}

// formatting

export fn rt_i32_to_string(value: i32, buf_ptr: [*]u8, buf_len: usize) usize {
    const buf = buf_ptr[0..buf_len];
    const result = std.fmt.bufPrint(buf, "{d}", .{value}) catch return 0;
    return result.len;
}

export fn rt_i64_to_string(value: i64, buf_ptr: [*]u8, buf_len: usize) usize {
    const buf = buf_ptr[0..buf_len];
    const result = std.fmt.bufPrint(buf, "{d}", .{value}) catch return 0;
    return result.len;
}

export fn rt_f64_to_string(value: f64, buf_ptr: [*]u8, buf_len: usize) usize {
    const buf = buf_ptr[0..buf_len];
    const result = std.fmt.bufPrint(buf, "{d}", .{value}) catch return 0;
    return result.len;
}

// memory

export fn rt_alloc(size: usize) ?[*]u8 {
    const slice = std.heap.c_allocator.alloc(u8, size) catch return null;
    return slice.ptr;
}

export fn rt_free(ptr: [*]u8, size: usize) void {
    std.heap.c_allocator.free(ptr[0..size]);
}

export fn rt_memcpy(dst: [*]u8, src: [*]const u8, len: usize) void {
    @memcpy(dst[0..len], src[0..len]);
}

export fn rt_memset(dst: [*]u8, value: u8, len: usize) void {
    @memset(dst[0..len], value);
}

// program control

export fn rt_exit(code: i32) noreturn {
    std.process.exit(@intCast(code));
}

export fn rt_abort() noreturn {
    std.process.abort();
}

export fn rt_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    const msg = msg_ptr[0..msg_len];
    const stderr_file = getStderr();
    stderr_file.writeAll("panic: ") catch {};
    stderr_file.writeAll(msg) catch {};
    stderr_file.writeAll("\n") catch {};
    std.process.abort();
}

export fn rt_debug(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    const stderr_file = getStderr();
    stderr_file.writeAll("[debug] ") catch {};
    stderr_file.writeAll(str) catch {};
    stderr_file.writeAll("\n") catch {};
}

test "rt_print_i32" {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{@as(i32, 42)}) catch unreachable;
    try std.testing.expectEqualStrings("42", result);
}

test "rt_string_eq" {
    const a = "hello";
    const b = "hello";
    const c = "world";

    try std.testing.expect(rt_string_eq(a.ptr, a.len, b.ptr, b.len));
    try std.testing.expect(!rt_string_eq(a.ptr, a.len, c.ptr, c.len));
}

test "rt_parse_i32" {
    const str = "123";
    const result = rt_parse_i32(str.ptr, str.len);
    try std.testing.expectEqual(@as(i32, 123), result);
}

test "rt_frame_alloc" {
    rt_frame_pool_reset();
    const frame = rt_frame_alloc();
    try std.testing.expect(frame != null);
    try std.testing.expectEqual(@as(usize, 0), frame.?.field_count);
}

test "rt_frame_add_string" {
    rt_frame_pool_reset();
    const frame = rt_frame_alloc().?;
    const key = "op";
    const value = "read";
    const success = rt_frame_add_string(frame, key.ptr, key.len, value.ptr, value.len);
    try std.testing.expect(success);
    try std.testing.expectEqual(@as(usize, 1), frame.field_count);
}
