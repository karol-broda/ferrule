const std = @import("std");
const ferrule = @import("ferrule");
const JsonBuilder = @import("json_builder.zig").JsonBuilder;
const types = @import("types.zig");
const hover = @import("hover.zig");
const transport = @import("transport.zig");
const document = @import("document.zig");
const analyzer = @import("analyzer.zig");
const diagnostics = ferrule.diagnostics;
const symbol_locations = ferrule.symbol_locations;

const LspRange = types.LspRange;
const RequestParams = types.RequestParams;
const Transport = transport.Transport;
const DocumentManager = document.DocumentManager;

pub const Server = struct {
    allocator: std.mem.Allocator,
    transport: Transport,
    documents: DocumentManager,
    debug_mode: bool,

    pub fn init(allocator: std.mem.Allocator) Server {
        return .{
            .allocator = allocator,
            .transport = Transport.init(allocator),
            .documents = DocumentManager.init(allocator),
            .debug_mode = std.process.hasEnvVarConstant("FERRULE_LSP_DEBUG"),
        };
    }

    pub fn deinit(self: *Server) void {
        self.documents.deinit();
    }

    pub fn run(self: *Server) !void {
        while (true) {
            const message = self.transport.readMessage() catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            defer self.allocator.free(message);
            try self.handleMessage(message);
        }
    }

    fn handleMessage(self: *Server, message: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message, .{}) catch return;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return;

        const method = root.object.get("method") orelse return;
        if (method != .string) return;

        const id = self.extractId(root.object.get("id"));
        const params = root.object.get("params");

        if (self.debug_mode) std.debug.print("[LSP] {s}\n", .{method.string});

        if (std.mem.eql(u8, method.string, "initialize")) {
            try self.handleInitialize(id);
        } else if (std.mem.eql(u8, method.string, "initialized")) {
            // nothing to do
        } else if (std.mem.eql(u8, method.string, "shutdown")) {
            try self.sendNullResponse(id);
        } else if (std.mem.eql(u8, method.string, "exit")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, method.string, "textDocument/didOpen")) {
            try self.handleDidOpen(params);
        } else if (std.mem.eql(u8, method.string, "textDocument/didChange")) {
            try self.handleDidChange(params);
        } else if (std.mem.eql(u8, method.string, "textDocument/didClose")) {
            try self.handleDidClose(params);
        } else if (std.mem.eql(u8, method.string, "textDocument/hover")) {
            try self.handleHover(id, params);
        } else if (std.mem.eql(u8, method.string, "textDocument/definition")) {
            try self.handleDefinition(id, params);
        } else if (std.mem.eql(u8, method.string, "textDocument/references")) {
            try self.handleReferences(id, params);
        }
    }

    fn extractId(_: *Server, id_val: ?std.json.Value) i64 {
        if (id_val) |id| {
            if (id == .integer) return id.integer;
        }
        return 0;
    }

    fn handleInitialize(self: *Server, id: i64) !void {
        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.fieldInt("id", id);
        try json.comma();
        try json.key("result");
        try json.objectStart();

        try json.key("capabilities");
        try json.objectStart();
        try json.key("textDocumentSync");
        try json.objectStart();
        try json.fieldBool("openClose", true);
        try json.comma();
        try json.fieldInt("change", 1);
        try json.objectEnd();
        try json.comma();
        try json.fieldBool("hoverProvider", true);
        try json.comma();
        try json.fieldBool("definitionProvider", true);
        try json.comma();
        try json.fieldBool("referencesProvider", true);
        try json.objectEnd();
        try json.comma();

        try json.key("serverInfo");
        try json.objectStart();
        try json.field("name", "ferrule-lsp");
        try json.comma();
        try json.field("version", "0.1.0");
        try json.objectEnd();

        try json.objectEnd();
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }

    fn handleDidOpen(self: *Server, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        const text_val = text_doc.object.get("text") orelse return;
        const version_val = text_doc.object.get("version") orelse return;

        if (uri_val != .string or text_val != .string or version_val != .integer) return;

        try self.documents.open(uri_val.string, text_val.string, @intCast(version_val.integer));

        try self.analyzeAndPublish(uri_val.string, text_val.string);
    }

    fn handleDidChange(self: *Server, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        const version_val = text_doc.object.get("version") orelse return;

        const content_changes = p.object.get("contentChanges") orelse return;
        if (content_changes != .array or content_changes.array.items.len == 0) return;

        const first_change = content_changes.array.items[0];
        if (first_change != .object) return;

        const text_val = first_change.object.get("text") orelse return;
        if (text_val != .string or uri_val != .string or version_val != .integer) return;

        const updated = try self.documents.update(uri_val.string, text_val.string, @intCast(version_val.integer));
        if (updated) {
            try self.analyzeAndPublish(uri_val.string, text_val.string);
        }
    }

    fn handleDidClose(self: *Server, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        if (uri_val != .string) return;

        self.documents.close(uri_val.string);
    }

    fn handleHover(self: *Server, id: i64, params: ?std.json.Value) !void {
        const req = RequestParams.extract(params) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const doc = self.documents.get(req.uri) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const info = doc.hover_table.findAt(req.line, req.char) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const content = try hover.formatHoverContent(self.allocator, info);
        defer self.allocator.free(content);

        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.fieldInt("id", id);
        try json.comma();
        try json.key("result");
        try json.objectStart();
        try json.key("contents");
        try json.objectStart();
        try json.field("kind", "markdown");
        try json.comma();
        try json.field("value", content);
        try json.objectEnd();
        try json.objectEnd();
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }

    fn handleDefinition(self: *Server, id: i64, params: ?std.json.Value) !void {
        const req = RequestParams.extract(params) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const doc = self.documents.get(req.uri) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const hover_result = doc.hover_table.findAt(req.line, req.char);

        // check for field with definition location
        if (hover_result) |info| {
            if (info.kind == .field) {
                if (info.field_def_loc) |field_def| {
                    try self.sendLocationResponse(id, req.uri, LspRange.fromFieldDefLoc(field_def));
                    return;
                }
            }
        }

        // try to find symbol definition
        const symbol_name = if (hover_result) |info|
            info.name
        else if (doc.location_table.findSymbolAt(req.line, req.char)) |name|
            name
        else
            null;

        if (symbol_name) |name| {
            if (doc.location_table.getDefinition(name)) |def_loc| {
                try self.sendLocationResponse(id, req.uri, LspRange.fromSymbolLocation(def_loc));
                return;
            }
        }

        try self.sendNullResponse(id);
    }

    fn handleReferences(self: *Server, id: i64, params: ?std.json.Value) !void {
        const req = RequestParams.extract(params) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const doc = self.documents.get(req.uri) orelse {
            try self.sendNullResponse(id);
            return;
        };

        const symbol_name = if (doc.hover_table.findAt(req.line, req.char)) |info|
            info.name
        else if (doc.location_table.findSymbolAt(req.line, req.char)) |name|
            name
        else
            null;

        if (symbol_name == null) {
            try self.sendNullResponse(id);
            return;
        }

        const refs = doc.location_table.getReferences(symbol_name.?) orelse &[_]symbol_locations.LocationInfo{};

        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.fieldInt("id", id);
        try json.comma();
        try json.key("result");
        try json.arrayStart();

        for (refs, 0..) |ref, i| {
            if (i > 0) try json.comma();
            try json.objectStart();
            try json.field("uri", req.uri);
            try json.comma();
            try json.key("range");
            try LspRange.fromSymbolLocation(ref).write(&json);
            try json.objectEnd();
        }

        try json.arrayEnd();
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }

    fn analyzeAndPublish(self: *Server, uri: []const u8, source: []const u8) !void {
        var result = analyzer.analyzeDocument(self.allocator, uri, source);

        // update document tables
        if (self.documents.get(uri)) |doc| {
            analyzer.updateDocumentWithAnalysis(doc, &result, self.allocator);
        }

        // publish diagnostics
        try self.publishDiagnostics(uri, result.diagnostics);
    }

    fn publishDiagnostics(self: *Server, uri: []const u8, diags: []const diagnostics.Diagnostic) !void {
        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.field("method", "textDocument/publishDiagnostics");
        try json.comma();
        try json.key("params");
        try json.objectStart();
        try json.field("uri", uri);
        try json.comma();
        try json.key("diagnostics");
        try json.arrayStart();

        for (diags, 0..) |diag, i| {
            if (i > 0) try json.comma();
            try self.writeDiagnostic(&json, diag);
        }

        try json.arrayEnd();
        try json.objectEnd();
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }

    fn writeDiagnostic(_: *Server, json: *JsonBuilder, diag: diagnostics.Diagnostic) !void {
        const severity: u8 = switch (diag.level) {
            .@"error" => 1,
            .warning => 2,
            .note => 3,
        };

        try json.objectStart();
        try json.key("range");
        try LspRange.fromDiagnosticLocation(diag.location).write(json);
        try json.comma();
        try json.fieldInt("severity", severity);
        try json.comma();
        try json.key("message");
        try json.raw("\"");
        try json.writeEscaped(diag.message);
        if (diag.hint) |hint| {
            try json.raw("\\n\\nhint: ");
            try json.writeEscaped(hint);
        }
        try json.raw("\"");
        try json.objectEnd();
    }

    fn sendNullResponse(self: *Server, id: i64) !void {
        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.fieldInt("id", id);
        try json.comma();
        try json.fieldNull("result");
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }

    fn sendLocationResponse(self: *Server, id: i64, uri: []const u8, range: LspRange) !void {
        var json = JsonBuilder.init(self.allocator);
        defer json.deinit();

        try json.objectStart();
        try json.field("jsonrpc", "2.0");
        try json.comma();
        try json.fieldInt("id", id);
        try json.comma();
        try json.key("result");
        try json.objectStart();
        try json.field("uri", uri);
        try json.comma();
        try json.key("range");
        try range.write(&json);
        try json.objectEnd();
        try json.objectEnd();

        try self.transport.sendMessage(json.items());
    }
};
