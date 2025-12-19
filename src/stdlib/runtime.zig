//! ferrule runtime library - provides runtime functions called by generated code
//! build as static library (libferrule_rt.a) and link with ferrule programs

const std = @import("std");
const posix = std.posix;

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
