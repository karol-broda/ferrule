//! Ferrule Standard Library Prelude
//!
//! This module exports all standard library types and functions
//! that are available to Ferrule programs.

pub const io = @import("io.zig");

// Re-export commonly used types
pub const Io = io.Io;
pub const IoError = io.IoError;

// Re-export I/O operations
pub const stdout = io.stdout;
pub const stderr = io.stderr;
pub const stdin = io.stdin;

// Runtime functions for codegen
pub const rt_print = io.rt_print;
pub const rt_println = io.rt_println;
pub const rt_print_i32 = io.rt_print_i32;
pub const rt_print_i64 = io.rt_print_i64;
pub const rt_print_f64 = io.rt_print_f64;
pub const rt_print_bool = io.rt_print_bool;

// Initialize standard library (called at program startup)
pub fn init() void {
    io.initGlobalIo();
}

// ============================================================================
// Built-in Types (for type checking)
// ============================================================================

/// Unit type - zero-size type representing no value
pub const Unit = void;

/// Never type - represents computations that never complete
pub const Never = noreturn;

// ============================================================================
// Result Type
// ============================================================================

/// Result type for fallible operations
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,

        const Self = @This();

        pub fn isOk(self: Self) bool {
            return self == .ok;
        }

        pub fn isErr(self: Self) bool {
            return self == .err;
        }

        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ok => |v| v,
                .err => @panic("called unwrap on err value"),
            };
        }

        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |v| v,
                .err => default,
            };
        }

        pub fn unwrapErr(self: Self) E {
            return switch (self) {
                .ok => @panic("called unwrapErr on ok value"),
                .err => |e| e,
            };
        }
    };
}

// ============================================================================
// Maybe Type (Option)
// ============================================================================

/// Maybe type for optional values
pub fn Maybe(comptime T: type) type {
    return union(enum) {
        some: T,
        none,

        const Self = @This();

        pub fn isSome(self: Self) bool {
            return self == .some;
        }

        pub fn isNone(self: Self) bool {
            return self == .none;
        }

        pub fn unwrap(self: Self) T {
            return switch (self) {
                .some => |v| v,
                .none => @panic("called unwrap on none value"),
            };
        }

        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .some => |v| v,
                .none => default,
            };
        }
    };
}

// ============================================================================
// String utilities
// ============================================================================

pub const string = struct {
    /// Concatenate two strings (allocates)
    pub fn concat(allocator: anytype, a: []const u8, b: []const u8) ![]u8 {
        const result = try allocator.alloc(u8, a.len + b.len);
        @memcpy(result[0..a.len], a);
        @memcpy(result[a.len..], b);
        return result;
    }

    /// Check if string starts with prefix
    pub fn startsWith(s: []const u8, prefix: []const u8) bool {
        if (prefix.len > s.len) return false;
        return std.mem.eql(u8, s[0..prefix.len], prefix);
    }

    /// Check if string ends with suffix
    pub fn endsWith(s: []const u8, suffix: []const u8) bool {
        if (suffix.len > s.len) return false;
        return std.mem.eql(u8, s[s.len - suffix.len ..], suffix);
    }

    /// Check if string contains substring
    pub fn contains(haystack: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, haystack, needle) != null;
    }

    /// Get length of string
    pub fn len(s: []const u8) usize {
        return s.len;
    }
};

const std = @import("std");

// ============================================================================
// Tests
// ============================================================================

test "Result type" {
    const IntResult = Result(i32, []const u8);

    const ok_val: IntResult = .{ .ok = 42 };
    try std.testing.expect(ok_val.isOk());
    try std.testing.expectEqual(@as(i32, 42), ok_val.unwrap());

    const err_val: IntResult = .{ .err = "error" };
    try std.testing.expect(err_val.isErr());
    try std.testing.expectEqualStrings("error", err_val.unwrapErr());
}

test "Maybe type" {
    const MaybeInt = Maybe(i32);

    const some_val: MaybeInt = .{ .some = 42 };
    try std.testing.expect(some_val.isSome());
    try std.testing.expectEqual(@as(i32, 42), some_val.unwrap());

    const none_val: MaybeInt = .none;
    try std.testing.expect(none_val.isNone());
    try std.testing.expectEqual(@as(i32, 0), none_val.unwrapOr(0));
}

test "string utilities" {
    try std.testing.expect(string.startsWith("hello world", "hello"));
    try std.testing.expect(!string.startsWith("hello world", "world"));
    try std.testing.expect(string.endsWith("hello world", "world"));
    try std.testing.expect(string.contains("hello world", "lo wo"));
    try std.testing.expectEqual(@as(usize, 11), string.len("hello world"));
}
