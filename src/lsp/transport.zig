const std = @import("std");

pub const Transport = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) Transport {
        return .{
            .allocator = allocator,
            .stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO },
            .stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO },
        };
    }

    // reads a complete lsp message from stdin
    pub fn readMessage(self: *Transport) ![]const u8 {
        var content_length: ?usize = null;

        // read headers
        while (true) {
            var line_buf: [1024]u8 = undefined;
            var line_len: usize = 0;

            // read until newline
            while (line_len < line_buf.len) {
                var byte_buf: [1]u8 = undefined;
                const bytes_read = self.stdin.read(&byte_buf) catch |err| {
                    if (err == error.EndOfStream and line_len > 0) break;
                    return err;
                };
                if (bytes_read == 0) {
                    if (line_len > 0) break;
                    return error.EndOfStream;
                }
                if (byte_buf[0] == '\n') break;
                line_buf[line_len] = byte_buf[0];
                line_len += 1;
            }

            const line = line_buf[0..line_len];
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
                line[0 .. line.len - 1]
            else
                line;

            // empty line marks end of headers
            if (trimmed.len == 0) break;

            // parse content-length header
            if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                content_length = try std.fmt.parseInt(usize, trimmed["Content-Length: ".len..], 10);
            }
        }

        // read content body
        if (content_length) |length| {
            const content = try self.allocator.alloc(u8, length);
            errdefer self.allocator.free(content);
            const bytes_read = try self.stdin.readAll(content);
            if (bytes_read != length) return error.UnexpectedEndOfStream;
            return content;
        }

        return error.MissingContentLength;
    }

    // writes an lsp message to stdout
    pub fn sendMessage(self: *Transport, content: []const u8) !void {
        var len_buf: [32]u8 = undefined;
        const len_str = try std.fmt.bufPrint(&len_buf, "{d}", .{content.len});
        _ = try self.stdout.write("Content-Length: ");
        _ = try self.stdout.write(len_str);
        _ = try self.stdout.write("\r\n\r\n");
        _ = try self.stdout.write(content);
    }
};
