//! Standard I/O module for Ferrule
//!
//! Provides stdin, stdout, and stderr operations with the `io` effect.
//! All I/O operations require an `Io` capability to be passed explicitly.

const std = @import("std");

/// I/O capability type - represents authority to perform I/O operations
pub const Io = struct {
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,

    /// Create a new Io capability with standard file descriptors
    pub fn init() Io {
        return .{
            .stdin = std.io.getStdIn(),
            .stdout = std.io.getStdOut(),
            .stderr = std.io.getStdErr(),
        };
    }

    /// Create an Io capability with custom streams (for testing)
    pub fn initCustom(stdin: std.fs.File, stdout: std.fs.File, stderr: std.fs.File) Io {
        return .{
            .stdin = stdin,
            .stdout = stdout,
            .stderr = stderr,
        };
    }
};

/// Error types for I/O operations
pub const IoError = error{
    EndOfStream,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    NotOpenForWriting,
    OperationAborted,
    WouldBlock,
    SystemResources,
    InputOutput,
    Unexpected,
};

/// Standard output operations
pub const stdout = struct {
    /// Print a string to stdout
    pub fn print(io: *const Io, str: []const u8) IoError!void {
        io.stdout.writeAll(str) catch |err| {
            return mapError(err);
        };
    }

    /// Print a string followed by a newline to stdout
    pub fn println(io: *const Io, str: []const u8) IoError!void {
        io.stdout.writeAll(str) catch |err| {
            return mapError(err);
        };
        io.stdout.writeAll("\n") catch |err| {
            return mapError(err);
        };
    }

    /// Print formatted output to stdout
    pub fn printf(io: *const Io, comptime fmt: []const u8, args: anytype) IoError!void {
        io.stdout.writer().print(fmt, args) catch |err| {
            return mapError(err);
        };
    }

    /// Flush stdout buffer
    pub fn flush(io: *const Io) IoError!void {
        // std.fs.File doesn't have a flush method for stdout in the same way
        // For unbuffered stdout this is a no-op
        _ = io;
    }
};

/// Standard error operations
pub const stderr = struct {
    /// Print a string to stderr
    pub fn print(io: *const Io, str: []const u8) IoError!void {
        io.stderr.writeAll(str) catch |err| {
            return mapError(err);
        };
    }

    /// Print a string followed by a newline to stderr
    pub fn println(io: *const Io, str: []const u8) IoError!void {
        io.stderr.writeAll(str) catch |err| {
            return mapError(err);
        };
        io.stderr.writeAll("\n") catch |err| {
            return mapError(err);
        };
    }

    /// Print formatted output to stderr
    pub fn printf(io: *const Io, comptime fmt: []const u8, args: anytype) IoError!void {
        io.stderr.writer().print(fmt, args) catch |err| {
            return mapError(err);
        };
    }
};

/// Standard input operations
pub const stdin = struct {
    /// Read a line from stdin (up to newline, newline not included)
    /// Caller owns the returned slice and must free it with the provided allocator
    pub fn readLine(io: *const Io, allocator: std.mem.Allocator) (IoError || std.mem.Allocator.Error)!?[]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        const reader = io.stdin.reader();

        while (true) {
            const byte = reader.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    if (buffer.items.len == 0) {
                        return null; // EOF with no data
                    }
                    break; // return accumulated data
                }
                return mapError(err);
            };

            if (byte == '\n') {
                break;
            }

            try buffer.append(byte);
        }

        return try buffer.toOwnedSlice();
    }

    /// Read exactly `count` bytes from stdin
    /// Returns null if EOF is reached before reading `count` bytes
    pub fn readExact(io: *const Io, buffer: []u8) IoError!?usize {
        const reader = io.stdin.reader();
        const bytes_read = reader.readAll(buffer) catch |err| {
            return mapError(err);
        };

        if (bytes_read == 0) {
            return null;
        }

        return bytes_read;
    }

    /// Read up to `buffer.len` bytes from stdin
    pub fn read(io: *const Io, buffer: []u8) IoError!usize {
        const reader = io.stdin.reader();
        return reader.read(buffer) catch |err| {
            return mapError(err);
        };
    }

    /// Read all available input from stdin until EOF
    /// Caller owns the returned slice and must free it with the provided allocator
    pub fn readAll(io: *const Io, allocator: std.mem.Allocator, max_size: usize) (IoError || std.mem.Allocator.Error)![]u8 {
        const reader = io.stdin.reader();
        return reader.readAllAlloc(allocator, max_size) catch |err| {
            if (err == error.OutOfMemory) {
                return error.OutOfMemory;
            }
            return mapError(@as(std.fs.File.ReadError, @errorCast(err)));
        };
    }
};

/// Map Zig standard library errors to Ferrule IoError
fn mapError(err: anytype) IoError {
    return switch (err) {
        error.BrokenPipe => IoError.BrokenPipe,
        error.ConnectionResetByPeer => IoError.ConnectionResetByPeer,
        error.ConnectionTimedOut => IoError.ConnectionTimedOut,
        error.NotOpenForReading => IoError.NotOpenForReading,
        error.NotOpenForWriting => IoError.NotOpenForWriting,
        error.OperationAborted => IoError.OperationAborted,
        error.WouldBlock => IoError.WouldBlock,
        error.SystemResources => IoError.SystemResources,
        error.InputOutput => IoError.InputOutput,
        error.EndOfStream => IoError.EndOfStream,
        else => IoError.Unexpected,
    };
}

// ============================================================================
// Runtime functions called by generated code
// ============================================================================

/// Global I/O capability for runtime use
var global_io: ?Io = null;

/// Initialize the global I/O capability (called at program startup)
pub fn initGlobalIo() void {
    global_io = Io.init();
}

/// Get the global I/O capability
pub fn getGlobalIo() *const Io {
    if (global_io == null) {
        initGlobalIo();
    }
    return &global_io.?;
}

/// Runtime function: print string to stdout (for codegen)
pub fn rt_print(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    const io = getGlobalIo();
    stdout.print(io, str) catch {};
}

/// Runtime function: println to stdout (for codegen)
pub fn rt_println(str_ptr: [*]const u8, str_len: usize) void {
    const str = str_ptr[0..str_len];
    const io = getGlobalIo();
    stdout.println(io, str) catch {};
}

/// Runtime function: print i32 to stdout (for codegen)
pub fn rt_print_i32(value: i32) void {
    const io = getGlobalIo();
    stdout.printf(io, "{d}", .{value}) catch {};
}

/// Runtime function: print i64 to stdout (for codegen)
pub fn rt_print_i64(value: i64) void {
    const io = getGlobalIo();
    stdout.printf(io, "{d}", .{value}) catch {};
}

/// Runtime function: print f64 to stdout (for codegen)
pub fn rt_print_f64(value: f64) void {
    const io = getGlobalIo();
    stdout.printf(io, "{d}", .{value}) catch {};
}

/// Runtime function: print bool to stdout (for codegen)
pub fn rt_print_bool(value: bool) void {
    const io = getGlobalIo();
    const str = if (value) "true" else "false";
    stdout.print(io, str) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "stdout.print" {
    // This test just verifies the function compiles correctly
    // Actual I/O testing would require mocking
    const io = Io.init();
    try stdout.print(&io, "test");
}

test "stderr.print" {
    const io = Io.init();
    try stderr.print(&io, "test error");
}
