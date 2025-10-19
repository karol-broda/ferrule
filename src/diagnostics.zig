const std = @import("std");

const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const blue = "\x1b[34m";
    const white = "\x1b[37m";
    const dim = "\x1b[2m";
};

pub const ColorConfig = struct {
    enabled: bool,

    pub fn init() ColorConfig {
        if (std.process.hasEnvVarConstant("NO_COLOR")) {
            return .{ .enabled = false };
        }

        const stderr_fd: std.posix.fd_t = std.posix.STDERR_FILENO;
        const is_tty = std.posix.isatty(stderr_fd);
        return .{ .enabled = is_tty };
    }

    pub fn reset(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.reset else "";
    }

    pub fn bold(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.bold else "";
    }

    pub fn red(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.red else "";
    }

    pub fn yellow(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.yellow else "";
    }

    pub fn cyan(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.cyan else "";
    }

    pub fn blue(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.blue else "";
    }

    pub fn white(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.white else "";
    }

    pub fn dim(self: ColorConfig) []const u8 {
        return if (self.enabled) Color.dim else "";
    }
};

pub const Diagnostic = struct {
    level: Level,
    message: []const u8,
    location: SourceLocation,
    hint: ?[]const u8,

    pub const Level = enum {
        @"error",
        warning,
        note,

        pub fn toString(self: Level) []const u8 {
            return switch (self) {
                .@"error" => "error",
                .warning => "warning",
                .note => "note",
            };
        }

        pub fn toColor(self: Level, colors: ColorConfig) []const u8 {
            return switch (self) {
                .@"error" => colors.red(),
                .warning => colors.yellow(),
                .note => colors.cyan(),
            };
        }
    };

    pub fn formatWithSource(
        self: Diagnostic,
        source_content: ?[]const u8,
        writer: anytype,
        colors: ColorConfig,
    ) !void {
        const level_color = self.level.toColor(colors);
        const bold = colors.bold();
        const reset = colors.reset();
        const blue = colors.blue();
        const cyan = colors.cyan();

        try writer.print("{s}{s}{s}: {s}{s}\n", .{
            bold,
            level_color,
            self.level.toString(),
            self.message,
            reset,
        });
        try writer.print("{s}  ┌─ {s}{s}:{d}:{d}{s}\n", .{
            blue,
            bold,
            self.location.file,
            self.location.line,
            self.location.column,
            reset,
        });

        if (source_content) |source| {
            const line_content = getLine(source, self.location.line);
            if (line_content) |line| {
                try writer.print("{s}  │{s}\n", .{ blue, reset });
                try writer.print("{s}{d: >3} │{s} {s}\n", .{
                    blue,
                    self.location.line,
                    reset,
                    line,
                });
                try writer.print("{s}  │{s} ", .{ blue, reset });

                // add spacing before the highlight
                var i: usize = 0;
                while (i < self.location.column - 1) : (i += 1) {
                    try writer.writeAll(" ");
                }

                // add the highlight carets
                try writer.writeAll(level_color);
                i = 0;
                const highlight_len = if (self.location.length > 0) self.location.length else 1;
                while (i < highlight_len) : (i += 1) {
                    try writer.writeAll("^");
                }
                try writer.print("{s}\n", .{reset});
            }
        }

        if (self.hint) |hint| {
            try writer.print("{s}  │{s}\n", .{ blue, reset });
            try writer.print("{s}  = {s}help:{s} {s}\n", .{ blue, cyan, reset, hint });
        }
    }

    pub fn format(
        self: Diagnostic,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const colors = ColorConfig.init();
        try self.formatWithSource(null, writer, colors);
    }

    fn getLine(source: []const u8, target_line: usize) ?[]const u8 {
        var line: usize = 1;
        var start: usize = 0;
        var i: usize = 0;

        while (i < source.len) : (i += 1) {
            if (source[i] == '\n') {
                if (line == target_line) {
                    return source[start..i];
                }
                line += 1;
                start = i + 1;
            }
        }

        if (line == target_line) {
            return source[start..];
        }

        return null;
    }
};

pub const SourceLocation = struct {
    file: []const u8,
    line: usize,
    column: usize,
    length: usize,
};

pub const DiagnosticList = struct {
    diagnostics: std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
    allocated_messages: std.ArrayList([]const u8),
    allocated_hints: std.ArrayList([]const u8),
    source_content: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) DiagnosticList {
        var diagnostics = std.ArrayList(Diagnostic){};
        diagnostics.clearRetainingCapacity();
        return .{
            .diagnostics = diagnostics,
            .allocator = allocator,
            .allocated_messages = std.ArrayList([]const u8){},
            .allocated_hints = std.ArrayList([]const u8){},
            .source_content = null,
        };
    }

    pub fn setSourceContent(self: *DiagnosticList, source: []const u8) void {
        self.source_content = source;
    }

    pub fn addError(
        self: *DiagnosticList,
        message: []const u8,
        location: SourceLocation,
        hint: ?[]const u8,
    ) !void {
        try self.allocated_messages.append(self.allocator, message);
        if (hint) |h| {
            try self.allocated_hints.append(self.allocator, h);
        }
        try self.diagnostics.append(self.allocator, .{
            .level = .@"error",
            .message = message,
            .location = location,
            .hint = hint,
        });
    }

    pub fn addWarning(
        self: *DiagnosticList,
        message: []const u8,
        location: SourceLocation,
        hint: ?[]const u8,
    ) !void {
        try self.allocated_messages.append(self.allocator, message);
        if (hint) |h| {
            try self.allocated_hints.append(self.allocator, h);
        }
        try self.diagnostics.append(self.allocator, .{
            .level = .warning,
            .message = message,
            .location = location,
            .hint = hint,
        });
    }

    pub fn addNote(
        self: *DiagnosticList,
        message: []const u8,
        location: SourceLocation,
        hint: ?[]const u8,
    ) !void {
        try self.allocated_messages.append(self.allocator, message);
        if (hint) |h| {
            try self.allocated_hints.append(self.allocator, h);
        }
        try self.diagnostics.append(self.allocator, .{
            .level = .note,
            .message = message,
            .location = location,
            .hint = hint,
        });
    }

    pub fn hasErrors(self: *const DiagnosticList) bool {
        for (self.diagnostics.items) |diag| {
            if (diag.level == .@"error") return true;
        }
        return false;
    }

    pub fn print(self: *const DiagnosticList, writer: anytype) !void {
        const colors = ColorConfig.init();
        for (self.diagnostics.items) |diag| {
            try diag.formatWithSource(self.source_content, writer, colors);
            try writer.writeAll("\n");
        }
    }

    pub fn deinit(self: *DiagnosticList) void {
        for (self.allocated_messages.items) |message| {
            self.allocator.free(message);
        }
        self.allocated_messages.deinit(self.allocator);
        for (self.allocated_hints.items) |hint| {
            self.allocator.free(hint);
        }
        self.allocated_hints.deinit(self.allocator);
        self.diagnostics.deinit(self.allocator);
    }
};
