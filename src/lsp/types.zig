const std = @import("std");
const ferrule = @import("ferrule");
const JsonBuilder = @import("json_builder.zig").JsonBuilder;
const diagnostics = ferrule.diagnostics;
const symbol_locations = ferrule.symbol_locations;
const hover_info = ferrule.hover_info;

pub const LspRange = struct {
    start_line: usize,
    start_char: usize,
    end_line: usize,
    end_char: usize,

    pub fn fromSourceLocation(line: usize, col: usize, length: usize) LspRange {
        const l = if (line > 0) line - 1 else 0;
        const c = if (col > 0) col - 1 else 0;
        return .{
            .start_line = l,
            .start_char = c,
            .end_line = l,
            .end_char = c + length,
        };
    }

    pub fn fromDiagnosticLocation(loc: diagnostics.Location) LspRange {
        return fromSourceLocation(loc.line, loc.column, loc.length);
    }

    pub fn fromSymbolLocation(loc: symbol_locations.LocationInfo) LspRange {
        return fromSourceLocation(loc.line, loc.column, loc.length);
    }

    pub fn fromFieldDefLoc(loc: hover_info.FieldDefinitionLoc) LspRange {
        return fromSourceLocation(loc.line, loc.column, loc.length);
    }

    pub fn write(self: LspRange, json: *JsonBuilder) !void {
        try json.objectStart();
        try json.key("start");
        try json.objectStart();
        try json.fieldInt("line", self.start_line);
        try json.comma();
        try json.fieldInt("character", self.start_char);
        try json.objectEnd();
        try json.comma();
        try json.key("end");
        try json.objectStart();
        try json.fieldInt("line", self.end_line);
        try json.comma();
        try json.fieldInt("character", self.end_char);
        try json.objectEnd();
        try json.objectEnd();
    }
};

// request params extraction
pub const RequestParams = struct {
    uri: []const u8,
    line: usize,
    char: usize,

    pub fn extract(params: ?std.json.Value) ?RequestParams {
        const p = params orelse return null;
        if (p != .object) return null;

        const text_doc = p.object.get("textDocument") orelse return null;
        if (text_doc != .object) return null;

        const uri_val = text_doc.object.get("uri") orelse return null;
        if (uri_val != .string) return null;

        const position = p.object.get("position") orelse return null;
        if (position != .object) return null;

        const line_val = position.object.get("line") orelse return null;
        const char_val = position.object.get("character") orelse return null;
        if (line_val != .integer or char_val != .integer) return null;

        return .{
            .uri = uri_val.string,
            .line = @as(usize, @intCast(line_val.integer)) + 1,
            .char = @as(usize, @intCast(char_val.integer)) + 1,
        };
    }
};
