const std = @import("std");
const ferrule = @import("ferrule");
const hover_info = ferrule.hover_info;
const symbol_locations = ferrule.symbol_locations;
const context = ferrule.context;

pub const DocumentState = struct {
    uri: []const u8,
    text: []const u8,
    version: i32,
    allocator: std.mem.Allocator,
    hover_table: hover_info.HoverInfoTable,
    location_table: symbol_locations.SymbolLocationTable,
    // compilation context that owns all interned data for hover_table and location_table
    compilation_context: *context.CompilationContext,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8, text: []const u8, version: i32) !DocumentState {
        // create a compilation context for this document
        const ctx = try allocator.create(context.CompilationContext);
        ctx.* = context.CompilationContext.init(allocator);

        return .{
            .uri = try allocator.dupe(u8, uri),
            .text = try allocator.dupe(u8, text),
            .version = version,
            .allocator = allocator,
            .hover_table = hover_info.HoverInfoTable.init(ctx),
            .location_table = symbol_locations.SymbolLocationTable.init(ctx),
            .compilation_context = ctx,
        };
    }

    pub fn deinit(self: *DocumentState) void {
        self.allocator.free(self.uri);
        self.allocator.free(self.text);
        // deinit hashmap structures
        self.hover_table.deinit();
        self.location_table.deinit();
        // free compilation context (this frees all interned data via arena)
        self.compilation_context.deinit();
        self.allocator.destroy(self.compilation_context);
    }

    pub fn updateText(self: *DocumentState, new_text: []const u8, new_version: i32) !void {
        const text_copy = try self.allocator.dupe(u8, new_text);
        self.allocator.free(self.text);
        self.text = text_copy;
        self.version = new_version;
    }
};

pub const DocumentManager = struct {
    documents: std.StringHashMap(DocumentState),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DocumentManager {
        return .{
            .documents = std.StringHashMap(DocumentState).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DocumentManager) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            var doc = entry.value_ptr.*;
            doc.deinit();
        }
        self.documents.deinit();
    }

    pub fn open(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        const doc = try DocumentState.init(self.allocator, uri, text, version);
        try self.documents.put(doc.uri, doc);
    }

    pub fn update(self: *DocumentManager, uri: []const u8, new_text: []const u8, new_version: i32) !bool {
        if (self.documents.getPtr(uri)) |doc| {
            try doc.updateText(new_text, new_version);
            return true;
        }
        return false;
    }

    pub fn close(self: *DocumentManager, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |entry| {
            var doc = entry.value;
            doc.deinit();
        }
    }

    pub fn get(self: *DocumentManager, uri: []const u8) ?*DocumentState {
        return self.documents.getPtr(uri);
    }

    pub fn getConst(self: *const DocumentManager, uri: []const u8) ?DocumentState {
        return self.documents.get(uri);
    }
};
