const std = @import("std");

pub const JsonBuilder = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JsonBuilder {
        return .{
            .buffer = std.ArrayList(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *JsonBuilder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn writer(self: *JsonBuilder) std.ArrayList(u8).Writer {
        return self.buffer.writer(self.allocator);
    }

    pub fn toOwnedSlice(self: *JsonBuilder) ![]const u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn items(self: *const JsonBuilder) []const u8 {
        return self.buffer.items;
    }

    pub fn writeString(self: *JsonBuilder, str: []const u8) !void {
        const w = self.writer();
        try w.writeByte('"');
        try self.writeEscaped(str);
        try w.writeByte('"');
    }

    pub fn writeEscaped(self: *JsonBuilder, str: []const u8) !void {
        const w = self.writer();
        for (str) |c| {
            switch (c) {
                '"' => try w.writeAll("\\\""),
                '\\' => try w.writeAll("\\\\"),
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                else => try w.writeByte(c),
            }
        }
    }

    pub fn raw(self: *JsonBuilder, str: []const u8) !void {
        try self.writer().writeAll(str);
    }

    pub fn int(self: *JsonBuilder, value: anytype) !void {
        try self.writer().print("{d}", .{value});
    }

    pub fn objectStart(self: *JsonBuilder) !void {
        try self.raw("{");
    }

    pub fn objectEnd(self: *JsonBuilder) !void {
        try self.raw("}");
    }

    pub fn arrayStart(self: *JsonBuilder) !void {
        try self.raw("[");
    }

    pub fn arrayEnd(self: *JsonBuilder) !void {
        try self.raw("]");
    }

    pub fn key(self: *JsonBuilder, k: []const u8) !void {
        try self.writeString(k);
        try self.raw(":");
    }

    pub fn comma(self: *JsonBuilder) !void {
        try self.raw(",");
    }

    pub fn field(self: *JsonBuilder, k: []const u8, v: []const u8) !void {
        try self.key(k);
        try self.writeString(v);
    }

    pub fn fieldInt(self: *JsonBuilder, k: []const u8, v: anytype) !void {
        try self.key(k);
        try self.int(v);
    }

    pub fn fieldBool(self: *JsonBuilder, k: []const u8, v: bool) !void {
        try self.key(k);
        try self.raw(if (v) "true" else "false");
    }

    pub fn fieldNull(self: *JsonBuilder, k: []const u8) !void {
        try self.key(k);
        try self.raw("null");
    }
};
