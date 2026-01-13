//! scoped logging system for the ferrule compiler
//!
//! provides hierarchical logging with configurable verbosity levels per scope.
//! scopes form a hierarchy (e.g., "semantic.type_checker" inherits from "semantic")
//! and can be enabled/disabled independently.
//!
//! usage:
//!   const log = Logger.init(.info);
//!   const scoped = log.scoped("semantic.type_checker");
//!   scoped.debug("checking function '{s}'", .{func_name});
//!
//! configuration via environment:
//!   FERRULE_LOG=semantic:debug,codegen:trace
//!   FERRULE_LOG=*:debug  (enable all at debug level)

const std = @import("std");
const builtin = @import("builtin");
const render = @import("render.zig");

const Renderer = render.Renderer;
const Theme = render.Theme;

/// log levels ordered from most verbose (trace) to least verbose (err)
/// each level includes all less verbose levels
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    off = 5,

    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .off => "OFF",
        };
    }

    pub fn fromString(str: []const u8) ?Level {
        const map = std.StaticStringMap(Level).initComptime(.{
            .{ "trace", .trace },
            .{ "debug", .debug },
            .{ "info", .info },
            .{ "warn", .warn },
            .{ "err", .err },
            .{ "error", .err },
            .{ "off", .off },
        });
        return map.get(str);
    }
};

/// scope override entry for per-scope log level configuration
pub const ScopeOverride = struct {
    scope: []const u8,
    level: Level,
};

/// timing span for performance measurement
/// automatically logs elapsed time when destroyed
pub const Span = struct {
    logger: *const Logger,
    scope: []const u8,
    name: []const u8,
    start_time: i64,
    enabled: bool,

    pub fn end(self: *Span) void {
        if (!self.enabled) return;

        const end_time = std.time.microTimestamp();
        const elapsed_us = end_time - self.start_time;
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_us)) / 1000.0;

        self.logger.logInternal(
            .debug,
            self.scope,
            "[timing] {s} completed in {d:.2}ms",
            .{ self.name, elapsed_ms },
        );
    }
};

/// main logger configuration and state
pub const Logger = struct {
    /// default log level for scopes without specific overrides
    default_level: Level,

    /// per-scope level overrides
    /// stored as a simple array for O(n) lookup; sufficient for typical usage
    scope_overrides: []const ScopeOverride,

    /// whether to include timestamps in output
    show_timestamps: bool,

    /// allocator for dynamic operations (optional)
    allocator: ?std.mem.Allocator,

    /// cached parsed overrides from environment
    parsed_overrides: ?[]ScopeOverride,

    /// creates a logger with the given default level
    pub fn init(default_level: Level) Logger {
        return .{
            .default_level = default_level,
            .scope_overrides = &[_]ScopeOverride{},
            .show_timestamps = false,
            .allocator = null,
            .parsed_overrides = null,
        };
    }

    /// creates a logger with allocator for dynamic configuration
    pub fn initWithAllocator(allocator: std.mem.Allocator, default_level: Level) Logger {
        var logger = init(default_level);
        logger.allocator = allocator;
        return logger;
    }

    /// frees dynamically allocated resources
    pub fn deinit(self: *Logger) void {
        if (self.allocator) |alloc| {
            if (self.parsed_overrides) |overrides| {
                alloc.free(overrides);
                self.parsed_overrides = null;
            }
        }
    }

    /// parses configuration from environment variable FERRULE_LOG
    /// format: "scope1:level,scope2:level" or "*:level" for global
    /// example: "semantic:debug,codegen.llvm:trace"
    pub fn configureFromEnv(self: *Logger) void {
        const env_value = std.posix.getenv("FERRULE_LOG") orelse return;
        self.parseConfig(env_value);
    }

    /// parses a configuration string
    pub fn parseConfig(self: *Logger, config: []const u8) void {
        if (self.allocator == null) return;
        const alloc = self.allocator.?;

        // free previous overrides if any
        if (self.parsed_overrides) |old| {
            alloc.free(old);
        }

        var overrides: std.ArrayList(ScopeOverride) = .empty;
        defer overrides.deinit(alloc);

        var iter = std.mem.splitScalar(u8, config, ',');
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;

            // find the colon separator
            const colon_pos = std.mem.indexOfScalar(u8, trimmed, ':');

            // support both "scope:level" and "scope" (defaults to debug)
            const scope = if (colon_pos) |pos| trimmed[0..pos] else trimmed;
            const level = if (colon_pos) |pos|
                Level.fromString(trimmed[pos + 1 ..]) orelse continue
            else
                .debug;

            // handle global wildcard
            if (std.mem.eql(u8, scope, "*")) {
                self.default_level = level;
            } else {
                overrides.append(alloc, .{ .scope = scope, .level = level }) catch continue;
            }
        }

        if (overrides.items.len > 0) {
            self.parsed_overrides = overrides.toOwnedSlice(alloc) catch null;
            if (self.parsed_overrides) |o| {
                self.scope_overrides = o;
            }
        }
    }

    /// sets static scope overrides (does not require allocator)
    pub fn setOverrides(self: *Logger, overrides: []const ScopeOverride) void {
        self.scope_overrides = overrides;
    }

    /// creates a scoped logger for a specific component
    pub fn scoped(self: *const Logger, scope: []const u8) ScopedLogger {
        return ScopedLogger{
            .logger = self,
            .scope = scope,
        };
    }

    /// determines the effective log level for a scope
    /// checks for exact match first, then walks up the hierarchy
    pub fn levelForScope(self: *const Logger, scope: []const u8) Level {
        // check for exact match
        for (self.scope_overrides) |override| {
            if (std.mem.eql(u8, override.scope, scope)) {
                return override.level;
            }
        }

        // check for prefix matches (parent scopes)
        // e.g., "semantic.type_checker.expr" inherits from "semantic.type_checker" or "semantic"
        var check_scope = scope;
        while (std.mem.lastIndexOfScalar(u8, check_scope, '.')) |dot_pos| {
            check_scope = check_scope[0..dot_pos];
            for (self.scope_overrides) |override| {
                if (std.mem.eql(u8, override.scope, check_scope)) {
                    return override.level;
                }
            }
        }

        return self.default_level;
    }

    /// checks if logging is enabled for a scope at a given level
    pub fn isEnabled(self: *const Logger, scope: []const u8, level: Level) bool {
        // in release builds with logging disabled, always return false
        if (comptime !loggingEnabled()) {
            return false;
        }
        const scope_level = self.levelForScope(scope);
        return @intFromEnum(level) >= @intFromEnum(scope_level);
    }

    /// starts a timing span for performance measurement
    pub fn startSpan(self: *const Logger, scope: []const u8, name: []const u8) Span {
        const enabled = self.isEnabled(scope, .debug);
        if (enabled) {
            self.logInternal(.debug, scope, "[timing] {s} started", .{name});
        }
        return Span{
            .logger = self,
            .scope = scope,
            .name = name,
            .start_time = std.time.microTimestamp(),
            .enabled = enabled,
        };
    }

    /// internal logging implementation using renderer for styled output
    fn logInternal(
        self: *const Logger,
        level: Level,
        scope: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        _ = self;
        if (comptime !loggingEnabled()) return;

        // use a stack-allocated buffer to build the log message
        var buf: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        // wrap in the deprecated GenericWriter interface for Renderer compatibility
        const any_writer = std.io.GenericWriter(@TypeOf(writer), @TypeOf(writer).Error, struct {
            fn write(w: @TypeOf(writer), bytes: []const u8) @TypeOf(writer).Error!usize {
                return w.write(bytes);
            }
        }.write){ .context = writer };

        var renderer = Renderer.init(any_writer.any());

        // format: [scope] LEVEL: message
        // render scope in magenta
        renderer.magenta("[") catch return;
        renderer.write(scope) catch return;
        renderer.magenta("]") catch return;
        renderer.space() catch return;

        // render level with appropriate color
        switch (level) {
            .trace => renderer.dim(level.toString()) catch return,
            .debug => renderer.cyan(level.toString()) catch return,
            .info => renderer.green(level.toString()) catch return,
            .warn => renderer.yellow(level.toString()) catch return,
            .err => renderer.red(level.toString()) catch return,
            .off => {},
        }

        renderer.write(": ") catch return;
        renderer.print(fmt, args) catch return;
        renderer.newline() catch return;

        // write the buffered output to stderr
        const output = fbs.getWritten();
        std.fs.File.stderr().writeAll(output) catch return;
    }

    /// direct logging methods for convenience
    pub fn trace(self: *const Logger, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
        if (self.isEnabled(scope, .trace)) {
            self.logInternal(.trace, scope, fmt, args);
        }
    }

    pub fn debug(self: *const Logger, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
        if (self.isEnabled(scope, .debug)) {
            self.logInternal(.debug, scope, fmt, args);
        }
    }

    pub fn info(self: *const Logger, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
        if (self.isEnabled(scope, .info)) {
            self.logInternal(.info, scope, fmt, args);
        }
    }

    pub fn warn(self: *const Logger, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
        if (self.isEnabled(scope, .warn)) {
            self.logInternal(.warn, scope, fmt, args);
        }
    }

    pub fn err(self: *const Logger, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
        if (self.isEnabled(scope, .err)) {
            self.logInternal(.err, scope, fmt, args);
        }
    }
};

/// lightweight scoped logger that captures a scope prefix
/// cheap to create and pass around
pub const ScopedLogger = struct {
    logger: *const Logger,
    scope: []const u8,

    /// creates a child logger with extended scope
    /// e.g., "semantic".child("type_checker") -> "semantic.type_checker"
    pub fn child(self: ScopedLogger, sub_scope: []const u8) ScopedLogger {
        // note: this creates a runtime string which may need allocation
        // for zero-allocation, use static scope strings
        return .{
            .logger = self.logger,
            .scope = sub_scope, // caller should provide full scope
        };
    }

    /// checks if logging is enabled at the given level
    pub fn isEnabled(self: ScopedLogger, level: Level) bool {
        return self.logger.isEnabled(self.scope, level);
    }

    /// starts a timing span
    pub fn startSpan(self: ScopedLogger, name: []const u8) Span {
        return self.logger.startSpan(self.scope, name);
    }

    /// trace level logging (most verbose)
    pub fn trace(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        if (comptime !loggingEnabled()) return;
        if (self.logger.isEnabled(self.scope, .trace)) {
            self.logger.logInternal(.trace, self.scope, fmt, args);
        }
    }

    /// debug level logging
    pub fn debug(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        if (comptime !loggingEnabled()) return;
        if (self.logger.isEnabled(self.scope, .debug)) {
            self.logger.logInternal(.debug, self.scope, fmt, args);
        }
    }

    /// info level logging
    pub fn info(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        if (comptime !loggingEnabled()) return;
        if (self.logger.isEnabled(self.scope, .info)) {
            self.logger.logInternal(.info, self.scope, fmt, args);
        }
    }

    /// warning level logging
    pub fn warn(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        if (comptime !loggingEnabled()) return;
        if (self.logger.isEnabled(self.scope, .warn)) {
            self.logger.logInternal(.warn, self.scope, fmt, args);
        }
    }

    /// error level logging (least verbose)
    pub fn err(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        if (comptime !loggingEnabled()) return;
        if (self.logger.isEnabled(self.scope, .err)) {
            self.logger.logInternal(.err, self.scope, fmt, args);
        }
    }
};

/// null logger that discards all output (for use when logging is disabled)
pub const NullLogger = struct {
    pub fn scoped(_: NullLogger, _: []const u8) NullScopedLogger {
        return .{};
    }

    pub fn isEnabled(_: NullLogger, _: []const u8, _: Level) bool {
        return false;
    }
};

pub const NullScopedLogger = struct {
    pub fn child(_: NullScopedLogger, _: []const u8) NullScopedLogger {
        return .{};
    }

    pub fn isEnabled(_: NullScopedLogger, _: Level) bool {
        return false;
    }

    pub fn startSpan(_: NullScopedLogger, _: []const u8) NullSpan {
        return .{};
    }

    pub fn trace(_: NullScopedLogger, comptime _: []const u8, _: anytype) void {}
    pub fn debug(_: NullScopedLogger, comptime _: []const u8, _: anytype) void {}
    pub fn info(_: NullScopedLogger, comptime _: []const u8, _: anytype) void {}
    pub fn warn(_: NullScopedLogger, comptime _: []const u8, _: anytype) void {}
    pub fn err(_: NullScopedLogger, comptime _: []const u8, _: anytype) void {}
};

pub const NullSpan = struct {
    pub fn end(_: *NullSpan) void {}
};

/// static disabled logger for use when no logger is configured
/// this avoids dangling pointer issues from stack-allocated loggers
var disabled_logger_storage: Logger = .{
    .default_level = .off,
    .scope_overrides = &[_]ScopeOverride{},
    .show_timestamps = false,
    .allocator = null,
    .parsed_overrides = null,
};
pub const disabled_logger: *const Logger = &disabled_logger_storage;

/// predefined scope constants for consistency
pub const Scopes = struct {
    pub const main = "main";
    pub const lexer = "lexer";
    pub const parser = "parser";
    pub const semantic = "semantic";
    pub const semantic_declarations = "semantic.declarations";
    pub const semantic_type_resolver = "semantic.type_resolver";
    pub const semantic_type_checker = "semantic.type_checker";
    pub const semantic_effects = "semantic.effects";
    pub const semantic_errors = "semantic.errors";
    pub const semantic_regions = "semantic.regions";
    pub const semantic_exhaustiveness = "semantic.exhaustiveness";
    pub const codegen = "codegen";
    pub const codegen_llvm = "codegen.llvm";
    pub const linker = "linker";
    pub const memory = "memory";
    pub const memory_interning = "memory.interning";
};

/// determines if logging is enabled at compile time
/// in release optimized builds, logging can be completely disabled
fn loggingEnabled() bool {
    return builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
}

/// creates a default logger configured from environment
pub fn defaultLogger(allocator: std.mem.Allocator) Logger {
    var logger = Logger.initWithAllocator(allocator, .warn);
    logger.configureFromEnv();
    return logger;
}

// ============================================================================
// tests
// ============================================================================

test "level ordering" {
    try std.testing.expect(@intFromEnum(Level.trace) < @intFromEnum(Level.debug));
    try std.testing.expect(@intFromEnum(Level.debug) < @intFromEnum(Level.info));
    try std.testing.expect(@intFromEnum(Level.info) < @intFromEnum(Level.warn));
    try std.testing.expect(@intFromEnum(Level.warn) < @intFromEnum(Level.err));
    try std.testing.expect(@intFromEnum(Level.err) < @intFromEnum(Level.off));
}

test "level from string" {
    try std.testing.expectEqual(Level.trace, Level.fromString("trace").?);
    try std.testing.expectEqual(Level.debug, Level.fromString("debug").?);
    try std.testing.expectEqual(Level.info, Level.fromString("info").?);
    try std.testing.expectEqual(Level.warn, Level.fromString("warn").?);
    try std.testing.expectEqual(Level.err, Level.fromString("err").?);
    try std.testing.expectEqual(Level.err, Level.fromString("error").?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromString("invalid"));
}

test "scope hierarchy matching" {
    const overrides = [_]ScopeOverride{
        .{ .scope = "semantic", .level = .debug },
        .{ .scope = "semantic.type_checker", .level = .trace },
    };

    var logger = Logger.init(.warn);
    logger.setOverrides(&overrides);

    // exact match
    try std.testing.expectEqual(Level.trace, logger.levelForScope("semantic.type_checker"));

    // parent match
    try std.testing.expectEqual(Level.debug, logger.levelForScope("semantic.declarations"));

    // grandchild inherits from parent
    try std.testing.expectEqual(Level.trace, logger.levelForScope("semantic.type_checker.expr"));

    // no match uses default
    try std.testing.expectEqual(Level.warn, logger.levelForScope("codegen"));
}

test "scoped logger" {
    var logger = Logger.init(.debug);
    const scoped_log = logger.scoped("test.scope");

    try std.testing.expect(scoped_log.isEnabled(.debug));
    try std.testing.expect(scoped_log.isEnabled(.info));
    try std.testing.expect(scoped_log.isEnabled(.warn));
    try std.testing.expect(scoped_log.isEnabled(.err));
    try std.testing.expect(!scoped_log.isEnabled(.trace));
}

test "config parsing" {
    var logger = Logger.initWithAllocator(std.testing.allocator, .warn);
    defer logger.deinit();

    logger.parseConfig("semantic:debug,codegen:trace");

    try std.testing.expectEqual(Level.debug, logger.levelForScope("semantic"));
    try std.testing.expectEqual(Level.trace, logger.levelForScope("codegen"));
    try std.testing.expectEqual(Level.warn, logger.levelForScope("parser"));
}

test "global config" {
    var logger = Logger.initWithAllocator(std.testing.allocator, .warn);
    defer logger.deinit();

    logger.parseConfig("*:debug");

    try std.testing.expectEqual(Level.debug, logger.default_level);
    try std.testing.expectEqual(Level.debug, logger.levelForScope("anything"));
}
