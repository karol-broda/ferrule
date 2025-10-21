const std = @import("std");
const ast = @import("ast.zig");
const symbol_table = @import("symbol_table.zig");
const LLVMBackend = @import("codegen/llvm_backend.zig").LLVMBackend;

pub const CodegenResult = struct {
    llvm_ir: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CodegenResult) void {
        self.allocator.free(self.llvm_ir);
    }
};

pub fn generateLLVMIR(
    allocator: std.mem.Allocator,
    module: ast.Module,
    symbols: *symbol_table.SymbolTable,
    diagnostics_list: *@import("diagnostics.zig").DiagnosticList,
    source_file: []const u8,
    module_name: []const u8,
) !CodegenResult {
    var backend = try LLVMBackend.init(allocator, module_name, symbols, diagnostics_list, source_file);
    defer backend.deinit();

    try backend.generateModule(module);

    const ir_string = try backend.emitToString();

    return CodegenResult{
        .llvm_ir = ir_string,
        .allocator = allocator,
    };
}
