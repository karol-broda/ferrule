const std = @import("std");
const render = @import("render.zig");

pub const Theme = render.Theme;
pub const Renderer = render.Renderer;
pub const Box = render.Box;

pub const DiagnosticLevel = enum {
    @"error",
    warning,
    note,

    pub fn toString(self: DiagnosticLevel) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
            .note => "note",
        };
    }
};

pub const Location = struct {
    file: []const u8,
    line: usize,
    column: usize,
    length: usize,
};

pub const Diagnostic = struct {
    level: DiagnosticLevel,
    message: []const u8,
    location: Location,
    hint: ?[]const u8,

    pub fn renderTo(self: Diagnostic, source_content: ?[]const u8, r: *Renderer) !void {
        const theme = r.theme;

        const level_color = switch (self.level) {
            .@"error" => theme.red(),
            .warning => theme.yellow(),
            .note => theme.cyan(),
        };

        try r.writer.writeAll(theme.bold());
        try r.writer.writeAll(level_color);
        try r.write(self.level.toString());
        try r.writer.writeAll(theme.reset());
        try r.write(": ");
        try r.write(self.message);
        try r.newline();

        if (source_content) |source| {
            const line_content = render.getLine(source, self.location.line);
            if (line_content) |line| {
                const line_num_width = render.countDigits(self.location.line);
                const gutter = if (line_num_width < 3) 3 else line_num_width;

                try r.spaces(gutter);
                try r.space();
                try r.dim(Box.top_left);
                try r.dim(Box.horizontal);
                try r.write("[");
                try r.blue(self.location.file);
                try r.write(":");
                try r.styledFmt(theme.magenta(), "{d}", .{self.location.line});
                try r.write(":");
                try r.styledFmt(theme.magenta(), "{d}", .{self.location.column});
                try r.write("]");
                try r.newline();

                try r.spaces(gutter);
                try r.space();
                try r.dim(Box.vertical);
                try r.newline();

                try r.spaces(gutter - line_num_width);
                try r.styledFmt(theme.magenta(), "{d}", .{self.location.line});
                try r.space();
                try r.dim(Box.vertical);
                try r.space();
                try r.write(line);
                try r.newline();

                try r.spaces(gutter);
                try r.space();
                try r.dim(Box.vertical);
                try r.space();

                var i: usize = 0;
                while (i < self.location.column - 1) : (i += 1) {
                    try r.space();
                }

                try r.writer.writeAll(theme.bold());
                try r.writer.writeAll(level_color);
                const highlight_len = if (self.location.length > 0) self.location.length else 1;
                i = 0;
                while (i < highlight_len) : (i += 1) {
                    try r.write(Box.horizontal);
                }
                try r.writer.writeAll(theme.reset());
                try r.newline();

                if (self.hint) |hint| {
                    try r.spaces(gutter);
                    try r.space();
                    try r.dim("╰");
                    try r.dim("─");
                    try r.space();
                    try r.cyan("help");
                    try r.dim(":");
                    try r.space();
                    try r.write(hint);
                    try r.newline();
                }
            }
        } else {
            try r.write("  ");
            try r.dim("at");
            try r.space();
            try r.write(self.location.file);
            try r.write(":");
            try r.print("{d}", .{self.location.line});
            try r.write(":");
            try r.print("{d}", .{self.location.column});
            try r.newline();

            if (self.hint) |hint| {
                try r.write("  ");
                try r.cyan("help:");
                try r.space();
                try r.write(hint);
                try r.newline();
            }
        }

        try r.newline();
    }

    pub fn format(
        self: Diagnostic,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        var r = Renderer.init(writer.any());
        try self.renderTo(null, &r);
    }

    pub fn formatWithSource(
        self: Diagnostic,
        source_content: ?[]const u8,
        writer: anytype,
        theme: Theme,
    ) !void {
        var r = Renderer.initWithTheme(writer.any(), theme);
        try self.renderTo(source_content, &r);
    }
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

    pub fn deinit(self: *DiagnosticList) void {
        for (self.allocated_messages.items) |msg| {
            self.allocator.free(msg);
        }
        self.allocated_messages.deinit(self.allocator);

        for (self.allocated_hints.items) |hint| {
            self.allocator.free(hint);
        }
        self.allocated_hints.deinit(self.allocator);

        self.diagnostics.deinit(self.allocator);
    }

    pub fn setSource(self: *DiagnosticList, source: []const u8) void {
        self.source_content = source;
    }

    pub fn setSourceContent(self: *DiagnosticList, source: []const u8) void {
        self.source_content = source;
    }

    pub fn addError(self: *DiagnosticList, message: []const u8, location: Location, hint: ?[]const u8) !void {
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

    pub fn addWarning(self: *DiagnosticList, message: []const u8, location: Location, hint: ?[]const u8) !void {
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

    pub fn addNote(self: *DiagnosticList, message: []const u8, location: Location, hint: ?[]const u8) !void {
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
            if (diag.level == .@"error") {
                return true;
            }
        }
        return false;
    }

    pub fn errorCount(self: *const DiagnosticList) usize {
        var count: usize = 0;
        for (self.diagnostics.items) |diag| {
            if (diag.level == .@"error") {
                count += 1;
            }
        }
        return count;
    }

    pub fn warningCount(self: *const DiagnosticList) usize {
        var count: usize = 0;
        for (self.diagnostics.items) |diag| {
            if (diag.level == .warning) {
                count += 1;
            }
        }
        return count;
    }

    pub fn render(self: *const DiagnosticList, r: *Renderer) !void {
        for (self.diagnostics.items) |diag| {
            try diag.renderTo(self.source_content, r);
        }
    }

    pub fn print(self: *const DiagnosticList, writer: anytype) !void {
        var r = Renderer.init(writer.any());
        try self.render(&r);
    }
};

pub const ColorConfig = Theme;
