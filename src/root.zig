//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// public exports for LSP and other consumers
pub const diagnostics = @import("diagnostics.zig");
pub const symbol_locations = @import("symbol_locations.zig");
pub const hover_info = @import("hover_info.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");
pub const semantic = @import("semantic.zig");
pub const types = @import("types.zig");
pub const symbol_table = @import("symbol_table.zig");
pub const context = @import("context.zig");
pub const logging = @import("logging.zig");

// import semantic tests
test {
    _ = @import("semantic/declaration_pass.zig");
    _ = @import("semantic/effect_checker.zig");
    _ = @import("semantic/error_checker.zig");
    _ = @import("semantic/exhaustiveness.zig");
    _ = @import("semantic/region_checker.zig");
    _ = @import("semantic/type_checker.zig");
    _ = @import("semantic/type_resolver.zig");
}

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
