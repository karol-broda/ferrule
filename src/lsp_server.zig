const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const semantic = @import("semantic.zig");
const diagnostics = @import("diagnostics.zig");
const hover_info = @import("hover_info.zig");
const symbol_locations = @import("symbol_locations.zig");

const JsonRpc = struct {
    const VERSION = "2.0";
};

const LspServer = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(DocumentState),
    initialized: bool,
    debug_mode: bool,

    const DocumentState = struct {
        uri: []const u8,
        text: []const u8,
        version: i32,
        allocator: std.mem.Allocator,
        hover_table: hover_info.HoverInfoTable,
        location_table: symbol_locations.SymbolLocationTable,

        pub fn deinit(self: *DocumentState) void {
            self.allocator.free(self.uri);
            self.allocator.free(self.text);
            self.hover_table.deinit();
            self.location_table.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) LspServer {
        const debug_mode = std.process.hasEnvVarConstant("FERRULE_LSP_DEBUG");
        return .{
            .allocator = allocator,
            .documents = std.StringHashMap(DocumentState).init(allocator),
            .initialized = false,
            .debug_mode = debug_mode,
        };
    }

    pub fn deinit(self: *LspServer) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            var doc = entry.value_ptr.*;
            doc.deinit();
        }
        self.documents.deinit();
    }

    pub fn run(self: *LspServer) !void {
        const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };

        while (true) {
            const message = self.readMessage(stdin_file) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            defer self.allocator.free(message);

            try self.handleMessage(message);
        }
    }

    fn readMessage(self: *LspServer, file: std.fs.File) ![]const u8 {
        var content_length: ?usize = null;

        // read headers
        while (true) {
            var line_buf: [1024]u8 = undefined;
            var line_len: usize = 0;

            // read until newline
            while (line_len < line_buf.len) {
                var byte_buf: [1]u8 = undefined;
                const bytes_read = file.read(&byte_buf) catch |err| {
                    if (err == error.EndOfStream and line_len > 0) break;
                    return err;
                };
                if (bytes_read == 0) {
                    if (line_len > 0) break;
                    return error.EndOfStream;
                }
                const byte = byte_buf[0];
                if (byte == '\n') break;
                line_buf[line_len] = byte;
                line_len += 1;
            }

            const line = line_buf[0..line_len];

            // trim \r if present
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
                line[0 .. line.len - 1]
            else
                line;

            if (trimmed.len == 0) break; // empty line separates headers from content

            if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                const length_str = trimmed["Content-Length: ".len..];
                content_length = try std.fmt.parseInt(usize, length_str, 10);
            }
        }

        if (content_length) |length| {
            const content = try self.allocator.alloc(u8, length);
            errdefer self.allocator.free(content);
            const bytes_read = try file.readAll(content);
            if (bytes_read != length) return error.UnexpectedEndOfStream;
            return content;
        }

        return error.MissingContentLength;
    }

    fn handleMessage(self: *LspServer, message: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message, .{}) catch |err| {
            std.debug.print("json parse error: {s}\n", .{@errorName(err)});
            return;
        };
        defer parsed.deinit();

        const root = parsed.value;

        if (root != .object) return;
        const obj = root.object;

        const method = obj.get("method") orelse {
            // response message, ignore for now
            return;
        };

        if (method != .string) return;
        const method_name = method.string;

        const id = obj.get("id");
        const params = obj.get("params");

        if (std.mem.eql(u8, method_name, "initialize")) {
            try self.handleInitialize(id, params);
        } else if (std.mem.eql(u8, method_name, "initialized")) {
            self.initialized = true;
        } else if (std.mem.eql(u8, method_name, "shutdown")) {
            try self.handleShutdown(id);
        } else if (std.mem.eql(u8, method_name, "exit")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, method_name, "textDocument/didOpen")) {
            try self.handleDidOpen(params);
        } else if (std.mem.eql(u8, method_name, "textDocument/didChange")) {
            try self.handleDidChange(params);
        } else if (std.mem.eql(u8, method_name, "textDocument/didClose")) {
            try self.handleDidClose(params);
        } else if (std.mem.eql(u8, method_name, "textDocument/hover")) {
            try self.handleHover(id, params);
        } else if (std.mem.eql(u8, method_name, "textDocument/definition")) {
            try self.handleDefinition(id, params);
        } else if (std.mem.eql(u8, method_name, "textDocument/references")) {
            try self.handleReferences(id, params);
        }
    }

    fn handleInitialize(self: *LspServer, id: ?std.json.Value, params: ?std.json.Value) !void {
        _ = params;

        const id_int = if (id) |i| i.integer else 0;

        var response_buf: std.ArrayList(u8) = .empty;
        defer response_buf.deinit(self.allocator);
        const response_writer = response_buf.writer(self.allocator);

        try response_writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"capabilities\":{{\"textDocumentSync\":{{\"openClose\":true,\"change\":1}},\"hoverProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true}},\"serverInfo\":{{\"name\":\"ferrule-lsp\",\"version\":\"0.1.0\"}}}}}}", .{id_int});
        try self.sendMessage(response_buf.items);
    }

    fn handleShutdown(self: *LspServer, id: ?std.json.Value) !void {
        const id_int = if (id) |i| i.integer else 0;

        var response_buf: std.ArrayList(u8) = .empty;
        defer response_buf.deinit(self.allocator);
        const response_writer = response_buf.writer(self.allocator);

        try response_writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":null}}", .{id_int});
        try self.sendMessage(response_buf.items);
    }

    fn handleDidOpen(self: *LspServer, params: ?std.json.Value) !void {
        if (params == null or params.? != .object) return;
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse return;
        if (text_doc != .object) return;
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse return;
        const text_val = text_doc_obj.get("text") orelse return;
        const version_val = text_doc_obj.get("version") orelse return;

        if (uri_val != .string or text_val != .string or version_val != .integer) return;

        const uri = try self.allocator.dupe(u8, uri_val.string);
        const text = try self.allocator.dupe(u8, text_val.string);
        const version = @as(i32, @intCast(version_val.integer));

        try self.documents.put(uri, .{
            .uri = uri,
            .text = text,
            .version = version,
            .allocator = self.allocator,
            .hover_table = hover_info.HoverInfoTable.init(self.allocator),
            .location_table = symbol_locations.SymbolLocationTable.init(self.allocator),
        });

        try self.analyzeDocument(uri, text);
    }

    fn handleDidChange(self: *LspServer, params: ?std.json.Value) !void {
        if (params == null or params.? != .object) return;
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse return;
        if (text_doc != .object) return;
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse return;
        const version_val = text_doc_obj.get("version") orelse return;

        const content_changes = params_obj.get("contentChanges") orelse return;
        if (content_changes != .array or content_changes.array.items.len == 0) return;

        const first_change = content_changes.array.items[0];
        if (first_change != .object) return;
        const change_obj = first_change.object;

        const text_val = change_obj.get("text") orelse return;
        if (text_val != .string or uri_val != .string or version_val != .integer) return;

        const uri = uri_val.string;
        const new_text = try self.allocator.dupe(u8, text_val.string);
        const version = @as(i32, @intCast(version_val.integer));

        if (self.documents.getPtr(uri)) |doc| {
            self.allocator.free(doc.text);
            doc.text = new_text;
            doc.version = version;
            try self.analyzeDocument(uri, new_text);
        }
    }

    fn handleDidClose(self: *LspServer, params: ?std.json.Value) !void {
        if (params == null or params.? != .object) return;
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse return;
        if (text_doc != .object) return;
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse return;
        if (uri_val != .string) return;

        const uri = uri_val.string;

        if (self.documents.fetchRemove(uri)) |entry| {
            var doc = entry.value;
            doc.deinit();
        }
    }

    fn analyzeDocument(self: *LspServer, uri: []const u8, source: []const u8) !void {
        // lex
        var lex = lexer.Lexer.init(source);
        var tokens: std.ArrayList(lexer.Token) = .empty;
        defer tokens.deinit(self.allocator);

        while (true) {
            const token = lex.nextToken();
            try tokens.append(self.allocator, token);
            if (token.type == .eof) break;
        }

        // parse
        var parse = parser.Parser.init(self.allocator, tokens.items);
        const module = parse.parse() catch {
            // send empty diagnostics on parse error for now
            try self.publishDiagnostics(uri, &[_]diagnostics.Diagnostic{});
            return;
        };
        defer module.deinit(self.allocator);

        // semantic analysis
        var analyzer = semantic.SemanticAnalyzer.init(self.allocator, uri, source);
        defer analyzer.deinit();

        _ = analyzer.analyze(module) catch {
            // still send diagnostics even on error
            try self.publishDiagnostics(uri, analyzer.diagnostics_list.diagnostics.items);
            // copy hover table and location table even on error
            if (self.documents.getPtr(uri)) |doc| {
                doc.hover_table.deinit();
                doc.hover_table = analyzer.hover_table;
                analyzer.hover_table = hover_info.HoverInfoTable.init(self.allocator);

                doc.location_table.deinit();
                doc.location_table = analyzer.location_table;
                analyzer.location_table = symbol_locations.SymbolLocationTable.init(self.allocator);
            }
            return;
        };

        try self.publishDiagnostics(uri, analyzer.diagnostics_list.diagnostics.items);

        // copy hover table and location table to document state
        if (self.documents.getPtr(uri)) |doc| {
            doc.hover_table.deinit();
            doc.hover_table = analyzer.hover_table;
            analyzer.hover_table = hover_info.HoverInfoTable.init(self.allocator);

            doc.location_table.deinit();
            doc.location_table = analyzer.location_table;
            analyzer.location_table = symbol_locations.SymbolLocationTable.init(self.allocator);
        }
    }

    fn publishDiagnostics(self: *LspServer, uri: []const u8, diags: []const diagnostics.Diagnostic) !void {
        var json_buf: std.ArrayList(u8) = .empty;
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"");
        try self.writeJsonString(writer, uri);
        try writer.writeAll("\",\"diagnostics\":[");

        for (diags, 0..) |diag, i| {
            if (i > 0) try writer.writeAll(",");
            try self.writeDiagnostic(writer, diag);
        }

        try writer.writeAll("]}}");

        try self.sendMessage(json_buf.items);
    }

    fn writeDiagnostic(self: *LspServer, writer: anytype, diag: diagnostics.Diagnostic) !void {
        const severity: u8 = switch (diag.level) {
            .@"error" => 1,
            .warning => 2,
            .note => 3,
        };

        // LSP uses 0-based lines and columns
        const line = if (diag.location.line > 0) diag.location.line - 1 else 0;
        const col = if (diag.location.column > 0) diag.location.column - 1 else 0;
        const end_col = col + diag.location.length;

        try writer.print("{{\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"severity\":{d},\"message\":\"", .{
            line,
            col,
            line,
            end_col,
            severity,
        });

        try self.writeJsonString(writer, diag.message);
        try writer.writeAll("\"");

        if (diag.hint) |hint| {
            try writer.writeAll(",\"code\":\"hint\",\"codeDescription\":{\"href\":\"");
            try self.writeJsonString(writer, hint);
            try writer.writeAll("\"}");
        }

        try writer.writeAll("}");
    }

    fn formatHoverContent(self: *LspServer, writer: anytype, info: hover_info.HoverInfo) !void {
        const kind_name = switch (info.kind) {
            .variable => "variable",
            .constant => "constant",
            .parameter => "parameter",
            .function => "function",
            .type_def => "type",
            .error_domain => "error domain",
        };

        try writer.print("**{s}** _{s}_\n\n", .{ info.name, kind_name });

        if (info.function_info) |func_info| {
            if (self.debug_mode) std.debug.print("[LSP] Formatting function hover, params.len={d}, param_names.len={d}\n", .{ func_info.params.len, func_info.param_names.len });

            try writer.writeAll("```ferrule\n");
            try writer.print("function {s}(", .{info.name});

            const param_count = @min(func_info.param_names.len, func_info.params.len);
            for (0..param_count) |i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}: ", .{func_info.param_names[i]});
                try func_info.params[i].format("", .{}, writer);
            }

            try writer.writeAll(") -> ");
            try func_info.return_type.format("", .{}, writer);

            if (func_info.effects.len > 0) {
                try writer.writeAll(" with [");
                for (func_info.effects, 0..) |effect, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(effect.toString());
                }
                try writer.writeAll("]");
            }

            if (func_info.error_domain) |domain| {
                try writer.print(" use error {s}", .{domain});
            }

            try writer.writeAll("\n```\n\n");

            if (func_info.effects.len > 0) {
                try writer.writeAll("**Effects:**");
                for (func_info.effects) |effect| {
                    try writer.print(" `{s}`", .{effect.toString()});
                }
                try writer.writeAll("\n\n");
            }

            if (func_info.error_domain) |domain| {
                try writer.print("**Error Domain:** `{s}`\n\n", .{domain});
            }
        } else if (info.domain_info) |domain_info| {
            if (self.debug_mode) std.debug.print("[LSP] Formatting domain hover, variants.len={d}\n", .{domain_info.variants.len});

            try writer.writeAll("```ferrule\n");
            try writer.print("domain {s} {{\n", .{info.name});

            for (domain_info.variants) |variant| {
                try writer.print("  {s}", .{variant.name});

                if (variant.field_names.len > 0) {
                    try writer.writeAll(" { ");
                    for (variant.field_names, variant.field_types, 0..) |field_name, field_type, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.print("{s}: ", .{field_name});
                        try field_type.format("", .{}, writer);
                    }
                    try writer.writeAll(" }");
                }

                try writer.writeAll("\n");
            }

            try writer.writeAll("}\n```");
        } else {
            try writer.writeAll("```ferrule\n");
            try info.resolved_type.format("", .{}, writer);
            try writer.writeAll("\n```");
        }
    }

    fn handleHover(self: *LspServer, id: ?std.json.Value, params: ?std.json.Value) !void {
        if (params == null or params.? != .object) {
            if (self.debug_mode) std.debug.print("[LSP] Hover: params is null or not object\n", .{});
            try self.sendNullResponse(id);
            return;
        }
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no textDocument\n", .{});
            try self.sendNullResponse(id);
            return;
        };
        if (text_doc != .object) {
            if (self.debug_mode) std.debug.print("[LSP] Hover: textDocument not object\n", .{});
            try self.sendNullResponse(id);
            return;
        }
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no uri\n", .{});
            try self.sendNullResponse(id);
            return;
        };
        if (uri_val != .string) {
            if (self.debug_mode) std.debug.print("[LSP] Hover: uri not string\n", .{});
            try self.sendNullResponse(id);
            return;
        }

        const position = params_obj.get("position") orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no position\n", .{});
            try self.sendNullResponse(id);
            return;
        };
        if (position != .object) {
            if (self.debug_mode) std.debug.print("[LSP] Hover: position not object\n", .{});
            try self.sendNullResponse(id);
            return;
        }
        const position_obj = position.object;

        const line_val = position_obj.get("line") orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no line\n", .{});
            try self.sendNullResponse(id);
            return;
        };
        const char_val = position_obj.get("character") orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no character\n", .{});
            try self.sendNullResponse(id);
            return;
        };

        if (line_val != .integer or char_val != .integer) {
            if (self.debug_mode) std.debug.print("[LSP] Hover: line or char not integer\n", .{});
            try self.sendNullResponse(id);
            return;
        }

        const uri = uri_val.string;
        const line = @as(usize, @intCast(line_val.integer)) + 1;
        const char = @as(usize, @intCast(char_val.integer)) + 1;

        if (self.debug_mode) std.debug.print("[LSP] Hover: uri={s}, line={d}, char={d}\n", .{ uri, line, char });

        const doc = self.documents.get(uri) orelse {
            if (self.debug_mode) std.debug.print("[LSP] Hover: document not found\n", .{});
            try self.sendNullResponse(id);
            return;
        };

        if (self.debug_mode) std.debug.print("[LSP] Hover: searching in {d} hover infos\n", .{doc.hover_table.infos.items.len});

        if (doc.hover_table.findAt(line, char)) |info| {
            if (self.debug_mode) std.debug.print("[LSP] Hover: found info for {s}\n", .{info.name});

            var content_buf: std.ArrayList(u8) = .empty;
            defer content_buf.deinit(self.allocator);
            const content_writer = content_buf.writer(self.allocator);

            try self.formatHoverContent(content_writer, info);

            var response_buf: std.ArrayList(u8) = .empty;
            defer response_buf.deinit(self.allocator);
            const writer = response_buf.writer(self.allocator);

            const id_int = if (id) |i| i.integer else 0;

            try writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"contents\":{{\"kind\":\"markdown\",\"value\":\"", .{id_int});
            try self.writeJsonString(writer, content_buf.items);
            try writer.writeAll("\"}}}");

            if (self.debug_mode) std.debug.print("[LSP] Hover: sending response: {s}\n", .{response_buf.items});
            try self.sendMessage(response_buf.items);
        } else {
            if (self.debug_mode) std.debug.print("[LSP] Hover: no info found at position\n", .{});
            try self.sendNullResponse(id);
        }
    }

    fn handleDefinition(self: *LspServer, id: ?std.json.Value, params: ?std.json.Value) !void {
        if (self.debug_mode) std.debug.print("[LSP] handleDefinition called\n", .{});

        if (params == null or params.? != .object) {
            if (self.debug_mode) std.debug.print("[LSP] Definition: params invalid\n", .{});
            try self.sendNullResponse(id);
            return;
        }
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (text_doc != .object) {
            try self.sendNullResponse(id);
            return;
        }
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (uri_val != .string) {
            try self.sendNullResponse(id);
            return;
        }

        const position = params_obj.get("position") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (position != .object) {
            try self.sendNullResponse(id);
            return;
        }
        const position_obj = position.object;

        const line_val = position_obj.get("line") orelse {
            try self.sendNullResponse(id);
            return;
        };
        const char_val = position_obj.get("character") orelse {
            try self.sendNullResponse(id);
            return;
        };

        if (line_val != .integer or char_val != .integer) {
            try self.sendNullResponse(id);
            return;
        }

        const uri = uri_val.string;
        const line = @as(usize, @intCast(line_val.integer)) + 1;
        const char = @as(usize, @intCast(char_val.integer)) + 1;

        if (self.debug_mode) std.debug.print("[LSP] Definition: uri={s}, line={d}, char={d}\n", .{ uri, line, char });

        const doc = self.documents.get(uri) orelse {
            if (self.debug_mode) std.debug.print("[LSP] Definition: document not found\n", .{});
            try self.sendNullResponse(id);
            return;
        };

        if (self.debug_mode) std.debug.print("[LSP] Definition: hover_table has {d} entries, location_table has {d} symbols\n", .{ doc.hover_table.infos.items.len, doc.location_table.symbols.count() });

        // first try to find the symbol using hover info (which tracks all identifier locations)
        const symbol_name = if (doc.hover_table.findAt(line, char)) |info|
            info.name
        else if (doc.location_table.findSymbolAt(line, char)) |name|
            name
        else
            null;

        if (self.debug_mode) {
            if (symbol_name) |name| {
                std.debug.print("[LSP] Definition: found symbol '{s}'\n", .{name});
            } else {
                std.debug.print("[LSP] Definition: no symbol found at position\n", .{});
            }
        }

        if (symbol_name) |name| {
            if (doc.location_table.getDefinition(name)) |def_loc| {
                if (self.debug_mode) std.debug.print("[LSP] Definition: found at line={d}, col={d}\n", .{ def_loc.line, def_loc.column });

                var response_buf: std.ArrayList(u8) = .empty;
                defer response_buf.deinit(self.allocator);
                const writer = response_buf.writer(self.allocator);

                const id_int = if (id) |i| i.integer else 0;
                const def_line = if (def_loc.line > 0) def_loc.line - 1 else 0;
                const def_col = if (def_loc.column > 0) def_loc.column - 1 else 0;

                try writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"uri\":\"", .{id_int});
                try self.writeJsonString(writer, uri);
                try writer.print("\",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}}}", .{
                    def_line,
                    def_col,
                    def_line,
                    def_col + def_loc.length,
                });

                try self.sendMessage(response_buf.items);
                return;
            }
        }

        try self.sendNullResponse(id);
    }

    fn handleReferences(self: *LspServer, id: ?std.json.Value, params: ?std.json.Value) !void {
        if (params == null or params.? != .object) {
            try self.sendNullResponse(id);
            return;
        }
        const params_obj = params.?.object;

        const text_doc = params_obj.get("textDocument") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (text_doc != .object) {
            try self.sendNullResponse(id);
            return;
        }
        const text_doc_obj = text_doc.object;

        const uri_val = text_doc_obj.get("uri") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (uri_val != .string) {
            try self.sendNullResponse(id);
            return;
        }

        const position = params_obj.get("position") orelse {
            try self.sendNullResponse(id);
            return;
        };
        if (position != .object) {
            try self.sendNullResponse(id);
            return;
        }
        const position_obj = position.object;

        const line_val = position_obj.get("line") orelse {
            try self.sendNullResponse(id);
            return;
        };
        const char_val = position_obj.get("character") orelse {
            try self.sendNullResponse(id);
            return;
        };

        if (line_val != .integer or char_val != .integer) {
            try self.sendNullResponse(id);
            return;
        }

        const uri = uri_val.string;
        const line = @as(usize, @intCast(line_val.integer)) + 1;
        const char = @as(usize, @intCast(char_val.integer)) + 1;

        const doc = self.documents.get(uri) orelse {
            try self.sendNullResponse(id);
            return;
        };

        // first try to find the symbol using hover info (which tracks all identifier locations)
        const symbol_name = if (doc.hover_table.findAt(line, char)) |info|
            info.name
        else if (doc.location_table.findSymbolAt(line, char)) |name|
            name
        else
            null;

        if (symbol_name) |name| {
            const references = doc.location_table.getReferences(name) orelse &[_]symbol_locations.LocationInfo{};

            var response_buf: std.ArrayList(u8) = .empty;
            defer response_buf.deinit(self.allocator);
            const writer = response_buf.writer(self.allocator);

            const id_int = if (id) |i| i.integer else 0;

            try writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":[", .{id_int});

            for (references, 0..) |ref_loc, i| {
                if (i > 0) try writer.writeAll(",");

                const ref_line = if (ref_loc.line > 0) ref_loc.line - 1 else 0;
                const ref_col = if (ref_loc.column > 0) ref_loc.column - 1 else 0;

                try writer.writeAll("{\"uri\":\"");
                try self.writeJsonString(writer, uri);
                try writer.print("\",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}", .{
                    ref_line,
                    ref_col,
                    ref_line,
                    ref_col + ref_loc.length,
                });
            }

            try writer.writeAll("]}");

            try self.sendMessage(response_buf.items);
            return;
        }

        try self.sendNullResponse(id);
    }

    fn sendNullResponse(self: *LspServer, id: ?std.json.Value) !void {
        const id_int = if (id) |i| i.integer else 0;
        var response_buf: std.ArrayList(u8) = .empty;
        defer response_buf.deinit(self.allocator);
        const writer = response_buf.writer(self.allocator);
        try writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":null}}", .{id_int});
        try self.sendMessage(response_buf.items);
    }

    fn writeJsonString(_: *LspServer, writer: anytype, str: []const u8) !void {
        for (str) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
    }

    fn sendMessage(_: *LspServer, content: []const u8) !void {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

        // write header
        _ = try stdout_file.write("Content-Length: ");
        var len_buf: [32]u8 = undefined;
        const len_str = try std.fmt.bufPrint(&len_buf, "{d}", .{content.len});
        _ = try stdout_file.write(len_str);
        _ = try stdout_file.write("\r\n\r\n");
        _ = try stdout_file.write(content);
    }

    fn sendResponse(self: *LspServer, comptime fmt_str: []const u8, args: anytype) !void {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);
        try writer.print(fmt_str, args);
        try self.sendMessage(buf.items);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var server = LspServer.init(allocator);
    defer server.deinit();

    try server.run();
}
