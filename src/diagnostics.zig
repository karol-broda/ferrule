const std = @import("std");

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
    };

    pub fn formatWithSource(
        self: Diagnostic,
        source_content: ?[]const u8,
        writer: anytype,
    ) !void {
        try writer.print("{s}: {s}\n", .{ self.level.toString(), self.message });
        try writer.print("  ┌─ {s}:{d}:{d}\n", .{ self.location.file, self.location.line, self.location.column });

        if (source_content) |source| {
            const line_content = getLine(source, self.location.line);
            if (line_content) |line| {
                try writer.print("  │\n", .{});
                try writer.print("{d: >3} │ {s}\n", .{ self.location.line, line });
                try writer.print("  │ ", .{});

                // add spacing before the highlight
                var i: usize = 0;
                while (i < self.location.column - 1) : (i += 1) {
                    try writer.writeAll(" ");
                }

                // add the highlight carets
                i = 0;
                const highlight_len = if (self.location.length > 0) self.location.length else 1;
                while (i < highlight_len) : (i += 1) {
                    try writer.writeAll("^");
                }
                try writer.writeAll("\n");
            }
        }

        if (self.hint) |hint| {
            try writer.print("  │\n", .{});
            try writer.print("  = help: {s}\n", .{hint});
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
        try self.formatWithSource(null, writer);
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
        for (self.diagnostics.items) |diag| {
            try diag.formatWithSource(self.source_content, writer);
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
