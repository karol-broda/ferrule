const std = @import("std");
const ast = @import("ast.zig");
const symbol_table = @import("symbol_table.zig");
const LLVMBackend = @import("codegen/llvm_backend.zig").LLVMBackend;
const context = @import("context.zig");

pub const CodegenResult = struct {
    llvm_ir: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CodegenResult) void {
        self.allocator.free(self.llvm_ir);
    }
};

pub fn generateLLVMIR(
    ctx: *context.CompilationContext,
    module: ast.Module,
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *@import("diagnostics.zig").DiagnosticList,
    source_file: []const u8,
    module_name: []const u8,
) !CodegenResult {
    const allocator = ctx.permanentAllocator();
    var backend = try LLVMBackend.init(ctx, module_name, symbols, diagnostics_list, source_file);
    defer backend.deinit();

    try backend.generateModule(module);

    const ir_string = try backend.emitToString();

    return CodegenResult{
        .llvm_ir = ir_string,
        .allocator = allocator,
    };
}

pub fn generateFiles(
    ctx: *context.CompilationContext,
    module: ast.Module,
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *@import("diagnostics.zig").DiagnosticList,
    source_file: []const u8,
    module_name: []const u8,
    output_base: []const u8,
) !void {
    const allocator = ctx.permanentAllocator();
    var backend = try LLVMBackend.init(ctx, module_name, symbols, diagnostics_list, source_file);
    defer backend.deinit();

    try backend.generateModule(module);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{output_base});
    defer allocator.free(ir_file);
    try backend.writeIRToFile(ir_file);

    // use llc to generate assembly from IR
    const asm_file = try std.fmt.allocPrint(allocator, "{s}.s", .{output_base});
    defer allocator.free(asm_file);
    const llc_cmd = try std.fmt.allocPrint(allocator, "llc {s} -o {s}", .{ ir_file, asm_file });
    defer allocator.free(llc_cmd);

    const llc_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-c", llc_cmd },
    }) catch |err| {
        std.debug.print("failed to run llc: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);

    if (llc_result.term.Exited != 0) {
        std.debug.print("llc failed:\n{s}\n", .{llc_result.stderr});
        return error.LLCFailed;
    }

    // use as to assemble to object file
    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{output_base});
    defer allocator.free(obj_file);
    const as_cmd = try std.fmt.allocPrint(allocator, "as {s} -o {s}", .{ asm_file, obj_file });
    defer allocator.free(as_cmd);

    const as_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-c", as_cmd },
    }) catch |err| {
        std.debug.print("failed to run as: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(as_result.stdout);
    defer allocator.free(as_result.stderr);

    if (as_result.term.Exited != 0) {
        std.debug.print("as failed:\n{s}\n", .{as_result.stderr});
        return error.ASFailed;
    }
}
