const std = @import("std");
const Server = @import("server.zig").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // check for --debug flag
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var server = Server.init(allocator);
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            server.debug_mode = true;
        }
    }
    defer server.deinit();

    try server.run();
}
