const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const llvm = @import("llvm_bindings.zig");
const TypeMapper = @import("llvm_types.zig").TypeMapper;
const ferruleContext = @import("../context.zig");

pub const LLVMBackend = struct {
    allocator: std.mem.Allocator,
    context: *llvm.ContextRef,
    module: *llvm.ModuleRef,
    builder: *llvm.BuilderRef,
    type_mapper: TypeMapper,

    // symbol tracking
    symbols: *symbol_table.SymbolTable,
    named_values: std.StringHashMap(*llvm.ValueRef),
    named_types: std.StringHashMap(types.ResolvedType),
    functions: std.StringHashMap(*llvm.ValueRef),

    // diagnostics tracking
    diagnostics_list: *@import("../diagnostics.zig").DiagnosticList,
    source_file: []const u8,

    // runtime functions
    rt_println: ?*llvm.ValueRef,
    rt_print: ?*llvm.ValueRef,
    rt_print_i32: ?*llvm.ValueRef,
    rt_print_i64: ?*llvm.ValueRef,
    rt_print_f64: ?*llvm.ValueRef,
    rt_print_bool: ?*llvm.ValueRef,
    rt_print_newline: ?*llvm.ValueRef,

    // current function context
    current_function: ?*llvm.ValueRef,
    current_function_type: ?types.ResolvedType,
    current_function_decl: ?ast.FunctionDecl,

    // error handling runtime functions
    rt_frame_alloc: ?*llvm.ValueRef,
    rt_frame_add_string: ?*llvm.ValueRef,
    rt_frame_pool_reset: ?*llvm.ValueRef,
    rt_error_print: ?*llvm.ValueRef,

    // compilation context for arena-based memory management
    // types stored in named_types are borrowed from the context's arena
    compilation_context: *ferruleContext.CompilationContext,

    pub fn init(ctx: *ferruleContext.CompilationContext, module_name: []const u8, symbols: *symbol_table.SymbolTable, diagnostics_list: *@import("../diagnostics.zig").DiagnosticList, source_file: []const u8) !LLVMBackend {
        const allocator = ctx.permanentAllocator();

        const context = llvm.contextCreate() orelse return error.LLVMContextCreationFailed;
        errdefer llvm.contextDispose(context);

        const module_name_z = try allocator.dupeZ(u8, module_name);
        defer allocator.free(module_name_z);

        const module = llvm.moduleCreate(module_name_z.ptr, context) orelse return error.LLVMModuleCreationFailed;
        errdefer llvm.moduleDispose(module);

        const builder = llvm.builderCreate(context) orelse return error.LLVMBuilderCreationFailed;
        errdefer llvm.builderDispose(builder);

        return .{
            .allocator = allocator,
            .context = context,
            .module = module,
            .builder = builder,
            .type_mapper = TypeMapper.init(context, allocator),
            .symbols = symbols,
            .named_values = std.StringHashMap(*llvm.ValueRef).init(allocator),
            .named_types = std.StringHashMap(types.ResolvedType).init(allocator),
            .functions = std.StringHashMap(*llvm.ValueRef).init(allocator),
            .diagnostics_list = diagnostics_list,
            .source_file = source_file,
            .rt_println = null,
            .rt_print = null,
            .rt_print_i32 = null,
            .rt_print_i64 = null,
            .rt_print_f64 = null,
            .rt_print_bool = null,
            .rt_print_newline = null,
            .current_function = null,
            .current_function_type = null,
            .current_function_decl = null,
            .rt_frame_alloc = null,
            .rt_frame_add_string = null,
            .rt_frame_pool_reset = null,
            .rt_error_print = null,
            .compilation_context = ctx,
        };
    }

    pub fn deinit(self: *LLVMBackend) void {
        self.named_values.deinit();
        // arena cleanup handles type memory; only the hashmap structure needs deinit
        self.named_types.deinit();

        self.functions.deinit();
        llvm.builderDispose(self.builder);
        llvm.moduleDispose(self.module);
        llvm.contextDispose(self.context);
    }

    pub fn generateModule(self: *LLVMBackend, module: ast.Module) !void {
        // declare runtime functions for I/O
        try self.declareRuntimeFunctions();

        // first pass: declare all functions
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.declareFunctionPrototype(stmt.function_decl);
            }
        }

        // collect top-level statements that need execution (not just declarations)
        var top_level_stmts: std.ArrayList(ast.Stmt) = .empty;
        defer top_level_stmts.deinit(self.allocator);

        var has_main = false;
        for (module.statements) |stmt| {
            switch (stmt) {
                .function_decl => |fd| {
                    if (std.mem.eql(u8, fd.name, "main")) {
                        has_main = true;
                    }
                },
                .package_decl, .domain_decl, .use_error, .type_decl, .error_decl, .import_decl => {
                    // declarations that don't need runtime execution
                },
                else => {
                    // statements that need runtime execution
                    try top_level_stmts.append(self.allocator, stmt);
                },
            }
        }

        // if there are top-level statements, generate an init function
        if (top_level_stmts.items.len > 0) {
            try self.generateTopLevelInit(top_level_stmts.items);
        }

        // second pass: generate function bodies
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.generateFunction(stmt.function_decl);
            }
        }

        // if no main function exists but there are top-level statements, generate a main
        if (!has_main and top_level_stmts.items.len > 0) {
            try self.generateDefaultMain();
        }
    }

    /// generate __ferrule_init function for top-level statements
    fn generateTopLevelInit(self: *LLVMBackend, stmts: []const ast.Stmt) !void {
        const void_type = llvm.voidType(self.context);
        var empty_params = [_]*llvm.TypeRef{};
        const func_type = llvm.functionType(void_type, &empty_params, 0, 0);

        const init_func = llvm.addFunction(self.module, "__ferrule_init", func_type);
        try self.functions.put("__ferrule_init", init_func);

        self.current_function = init_func;
        defer self.current_function = null;

        // create entry block
        const entry_block = llvm.appendBasicBlock(self.context, init_func, "entry\x00");
        llvm.positionBuilderAtEnd(self.builder, entry_block);

        // clear named values for this scope
        self.named_values.clearRetainingCapacity();
        self.named_types.clearRetainingCapacity();

        // generate each top-level statement
        for (stmts) |stmt| {
            self.generateStatement(stmt) catch {
                // log error but continue
                continue;
            };
        }

        // add return void
        _ = llvm.buildRetVoid(self.builder);
    }

    /// generate a default main that calls __ferrule_init and returns 0
    fn generateDefaultMain(self: *LLVMBackend) !void {
        const i32_type = llvm.int32Type(self.context);
        var empty_params = [_]*llvm.TypeRef{};
        const func_type = llvm.functionType(i32_type, &empty_params, 0, 0);

        const main_func = llvm.addFunction(self.module, "main", func_type);
        try self.functions.put("main", main_func);

        self.current_function = main_func;
        defer self.current_function = null;

        // create entry block
        const entry_block = llvm.appendBasicBlock(self.context, main_func, "entry\x00");
        llvm.positionBuilderAtEnd(self.builder, entry_block);

        // call __ferrule_init
        const init_func = self.functions.get("__ferrule_init") orelse return error.FunctionNotFound;
        const void_type = llvm.voidType(self.context);
        var init_params = [_]*llvm.TypeRef{};
        const init_func_type = llvm.functionType(void_type, &init_params, 0, 0);
        var empty_args = [_]*llvm.ValueRef{};
        _ = llvm.buildCall(self.builder, init_func_type, init_func, &empty_args, 0, "\x00");

        // return 0
        const zero = llvm.constInt(i32_type, 0, 0);
        _ = llvm.buildRet(self.builder, zero);
    }

    /// Declare external runtime functions for I/O and other standard operations
    fn declareRuntimeFunctions(self: *LLVMBackend) !void {
        // i8* type for string pointers
        const i8_type = llvm.int8Type(self.context);
        const i8_ptr_type = llvm.pointerType(i8_type, 0);

        // integer types
        const i32_type = llvm.int32Type(self.context);
        const i64_type = llvm.int64Type(self.context);
        const i64_size_type = llvm.int64Type(self.context); // usize is typically i64
        const f64_type = llvm.doubleType(self.context);
        const i1_type = llvm.int1Type(self.context);
        const void_type = llvm.voidType(self.context);

        // rt_println(str_ptr: *i8, str_len: i64) -> void
        var println_params = [_]*llvm.TypeRef{ i8_ptr_type, i64_size_type };
        const println_type = llvm.functionType(void_type, &println_params, 2, 0);
        self.rt_println = llvm.addFunction(self.module, "rt_println", println_type);

        // rt_print(str_ptr: *i8, str_len: i64) -> void
        var print_params = [_]*llvm.TypeRef{ i8_ptr_type, i64_size_type };
        const print_type = llvm.functionType(void_type, &print_params, 2, 0);
        self.rt_print = llvm.addFunction(self.module, "rt_print", print_type);

        // rt_print_i32(value: i32) -> void
        var print_i32_params = [_]*llvm.TypeRef{i32_type};
        const print_i32_type = llvm.functionType(void_type, &print_i32_params, 1, 0);
        self.rt_print_i32 = llvm.addFunction(self.module, "rt_print_i32", print_i32_type);

        // rt_print_i64(value: i64) -> void
        var print_i64_params = [_]*llvm.TypeRef{i64_type};
        const print_i64_type = llvm.functionType(void_type, &print_i64_params, 1, 0);
        self.rt_print_i64 = llvm.addFunction(self.module, "rt_print_i64", print_i64_type);

        // rt_print_f64(value: f64) -> void
        var print_f64_params = [_]*llvm.TypeRef{f64_type};
        const print_f64_type = llvm.functionType(void_type, &print_f64_params, 1, 0);
        self.rt_print_f64 = llvm.addFunction(self.module, "rt_print_f64", print_f64_type);

        // rt_print_bool(value: i1) -> void
        var print_bool_params = [_]*llvm.TypeRef{i1_type};
        const print_bool_type = llvm.functionType(void_type, &print_bool_params, 1, 0);
        self.rt_print_bool = llvm.addFunction(self.module, "rt_print_bool", print_bool_type);

        var empty_params = [_]*llvm.TypeRef{};
        const print_newline_type = llvm.functionType(void_type, &empty_params, 0, 0);
        self.rt_print_newline = llvm.addFunction(self.module, "rt_print_newline", print_newline_type);

        // error handling runtime functions
        // rt_frame_alloc() -> *ErrorFrame (i8*)
        const frame_ptr_type = i8_ptr_type;
        const frame_alloc_type = llvm.functionType(frame_ptr_type, &empty_params, 0, 0);
        self.rt_frame_alloc = llvm.addFunction(self.module, "rt_frame_alloc", frame_alloc_type);

        // rt_frame_add_string(frame: *ErrorFrame, key_ptr: *i8, key_len: usize, value_ptr: *i8, value_len: usize) -> bool
        var frame_add_string_params = [_]*llvm.TypeRef{ frame_ptr_type, i8_ptr_type, i64_size_type, i8_ptr_type, i64_size_type };
        const frame_add_string_type = llvm.functionType(i1_type, &frame_add_string_params, 5, 0);
        self.rt_frame_add_string = llvm.addFunction(self.module, "rt_frame_add_string", frame_add_string_type);

        // rt_frame_pool_reset() -> void
        const frame_pool_reset_type = llvm.functionType(void_type, &empty_params, 0, 0);
        self.rt_frame_pool_reset = llvm.addFunction(self.module, "rt_frame_pool_reset", frame_pool_reset_type);

        // rt_error_print(domain_ptr: *i8, domain_len: usize, variant_ptr: *i8, variant_len: usize, frame: *ErrorFrame) -> void
        var error_print_params = [_]*llvm.TypeRef{ i8_ptr_type, i64_size_type, i8_ptr_type, i64_size_type, frame_ptr_type };
        const error_print_type = llvm.functionType(void_type, &error_print_params, 5, 0);
        self.rt_error_print = llvm.addFunction(self.module, "rt_error_print", error_print_type);
    }

    fn generateBuiltinCall(self: *LLVMBackend, func_name: []const u8, args: []*ast.Expr) !*llvm.ValueRef {
        const void_type = llvm.voidType(self.context);
        const i8_type = llvm.int8Type(self.context);
        const i8_ptr_type = llvm.pointerType(i8_type, 0);
        const i32_type = llvm.int32Type(self.context);
        const i64_type = llvm.int64Type(self.context);
        const f64_type = llvm.doubleType(self.context);
        const i1_type = llvm.int1Type(self.context);

        if (std.mem.eql(u8, func_name, "println") or std.mem.eql(u8, func_name, "print")) {
            // println/print take a String which is { ptr, len }
            if (args.len != 1) return error.ExpressionNotImplemented;

            const str_val = try self.generateExpression(args[0]);

            // String is a struct { ptr: *i8, len: i64 }
            // Extract ptr and len from the struct
            const ptr_val = llvm.buildExtractValue(self.builder, str_val, 0, "str.ptr\x00");
            const len_val = llvm.buildExtractValue(self.builder, str_val, 1, "str.len\x00");

            var call_args = [_]*llvm.ValueRef{ ptr_val, len_val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 2, 0);

            const rt_func = if (std.mem.eql(u8, func_name, "println"))
                self.rt_println orelse return error.FunctionNotFound
            else
                self.rt_print orelse return error.FunctionNotFound;

            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 2, "");
        } else if (std.mem.eql(u8, func_name, "print_i32")) {
            if (args.len != 1) return error.ExpressionNotImplemented;
            const val = try self.generateExpression(args[0]);

            var call_args = [_]*llvm.ValueRef{val};
            var param_types = [_]*llvm.TypeRef{i32_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, 0);

            const rt_func = self.rt_print_i32 orelse return error.FunctionNotFound;
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 1, "");
        } else if (std.mem.eql(u8, func_name, "print_i64")) {
            if (args.len != 1) return error.ExpressionNotImplemented;
            const val = try self.generateExpression(args[0]);

            var call_args = [_]*llvm.ValueRef{val};
            var param_types = [_]*llvm.TypeRef{i64_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, 0);

            const rt_func = self.rt_print_i64 orelse return error.FunctionNotFound;
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 1, "");
        } else if (std.mem.eql(u8, func_name, "print_f64")) {
            if (args.len != 1) return error.ExpressionNotImplemented;
            const val = try self.generateExpression(args[0]);

            var call_args = [_]*llvm.ValueRef{val};
            var param_types = [_]*llvm.TypeRef{f64_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, 0);

            const rt_func = self.rt_print_f64 orelse return error.FunctionNotFound;
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 1, "");
        } else if (std.mem.eql(u8, func_name, "print_bool")) {
            if (args.len != 1) return error.ExpressionNotImplemented;
            const val = try self.generateExpression(args[0]);

            var call_args = [_]*llvm.ValueRef{val};
            var param_types = [_]*llvm.TypeRef{i1_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, 0);

            const rt_func = self.rt_print_bool orelse return error.FunctionNotFound;
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 1, "");
        } else if (std.mem.eql(u8, func_name, "print_newline")) {
            var empty_params = [_]*llvm.TypeRef{};
            const func_type = llvm.functionType(void_type, &empty_params, 0, 0);
            const rt_func = self.rt_print_newline orelse return error.FunctionNotFound;
            var empty_args = [_]*llvm.ValueRef{};
            return llvm.buildCall(self.builder, func_type, rt_func, &empty_args, 0, "");
        } else if (std.mem.eql(u8, func_name, "read_char")) {
            var empty_params = [_]*llvm.TypeRef{};
            const func_type = llvm.functionType(i32_type, &empty_params, 0, 0);
            const rt_func = llvm.getNamedFunction(self.module, "rt_read_char") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_read_char", func_type);
            };
            var empty_args = [_]*llvm.ValueRef{};
            return llvm.buildCall(self.builder, func_type, rt_func, &empty_args, 0, "readchar\x00");
        } else if (std.mem.eql(u8, func_name, "print_i8")) {
            if (args.len != 1) return error.ExpressionNotImplemented;
            const val = try self.generateExpression(args[0]);

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{val};
            var param_types = [_]*llvm.TypeRef{i8_type_local};
            const func_type = llvm.functionType(void_type, &param_types, 1, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_print_i8") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_print_i8", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 1, "");
        } else if (std.mem.eql(u8, func_name, "dbg_i32")) {
            if (args.len != 2) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const val = try self.generateExpression(args[1]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");

            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, i32_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_i32") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_i32", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "dbg_i64")) {
            if (args.len != 2) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const val = try self.generateExpression(args[1]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");

            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_i64") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_i64", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "dbg_f64")) {
            if (args.len != 2) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const val = try self.generateExpression(args[1]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");

            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, f64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_f64") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_f64", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "dbg_bool")) {
            if (args.len != 2) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const val = try self.generateExpression(args[1]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");

            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, i1_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_bool") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_bool", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "dbg_str")) {
            if (args.len != 2) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const str_val = try self.generateExpression(args[1]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");
            const str_ptr = llvm.buildExtractValue(self.builder, str_val, 0, "str.ptr\x00");
            const str_len = llvm.buildExtractValue(self.builder, str_val, 1, "str.len\x00");

            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, str_ptr, str_len };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, i8_ptr_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 4, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_str") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_str", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 4, "");
        } else if (std.mem.eql(u8, func_name, "print_result_i32")) {
            if (args.len != 3) return error.ExpressionNotImplemented;
            const tag_val = try self.generateExpression(args[0]);
            const value_val = try self.generateExpression(args[1]);
            const error_code_val = try self.generateExpression(args[2]);

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{ tag_val, value_val, error_code_val };
            var param_types = [_]*llvm.TypeRef{ i8_type_local, i32_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_print_result_i32") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_print_result_i32", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "print_result_i64")) {
            if (args.len != 3) return error.ExpressionNotImplemented;
            const tag_val = try self.generateExpression(args[0]);
            const value_val = try self.generateExpression(args[1]);
            const error_code_val = try self.generateExpression(args[2]);

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{ tag_val, value_val, error_code_val };
            var param_types = [_]*llvm.TypeRef{ i8_type_local, i64_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_print_result_i64") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_print_result_i64", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "print_result_f64")) {
            if (args.len != 3) return error.ExpressionNotImplemented;
            const tag_val = try self.generateExpression(args[0]);
            const value_val = try self.generateExpression(args[1]);
            const error_code_val = try self.generateExpression(args[2]);

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{ tag_val, value_val, error_code_val };
            var param_types = [_]*llvm.TypeRef{ i8_type_local, f64_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_print_result_f64") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_print_result_f64", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "print_result_bool")) {
            if (args.len != 3) return error.ExpressionNotImplemented;
            const tag_val = try self.generateExpression(args[0]);
            const value_val = try self.generateExpression(args[1]);
            const error_code_val = try self.generateExpression(args[2]);

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{ tag_val, value_val, error_code_val };
            var param_types = [_]*llvm.TypeRef{ i8_type_local, i1_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 3, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_print_result_bool") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_print_result_bool", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 3, "");
        } else if (std.mem.eql(u8, func_name, "dbg_result_i32")) {
            if (args.len != 4) return error.ExpressionNotImplemented;
            const label_val = try self.generateExpression(args[0]);
            const tag_val = try self.generateExpression(args[1]);
            const value_val = try self.generateExpression(args[2]);
            const error_code_val = try self.generateExpression(args[3]);

            const label_ptr = llvm.buildExtractValue(self.builder, label_val, 0, "label.ptr\x00");
            const label_len = llvm.buildExtractValue(self.builder, label_val, 1, "label.len\x00");

            const i8_type_local = llvm.int8Type(self.context);
            var call_args = [_]*llvm.ValueRef{ label_ptr, label_len, tag_val, value_val, error_code_val };
            var param_types = [_]*llvm.TypeRef{ i8_ptr_type, i64_type, i8_type_local, i32_type, i64_type };
            const func_type = llvm.functionType(void_type, &param_types, 5, 0);

            const rt_func = llvm.getNamedFunction(self.module, "rt_dbg_result_i32") orelse blk: {
                break :blk llvm.addFunction(self.module, "rt_dbg_result_i32", func_type);
            };
            return llvm.buildCall(self.builder, func_type, rt_func, &call_args, 5, "");
        }

        return error.FunctionNotFound;
    }

    fn declareFunctionPrototype(self: *LLVMBackend, func_decl: ast.FunctionDecl) !void {
        const symbol = self.symbols.global_scope.symbols.get(func_decl.name) orelse return error.SymbolNotFound;

        if (symbol != .function) return error.NotAFunction;
        const func_info = symbol.function;

        // map parameter types
        const param_types = try self.allocator.alloc(*llvm.TypeRef, func_info.params.len);
        defer self.allocator.free(param_types);

        for (func_info.params, 0..) |param_type, i| {
            param_types[i] = try self.type_mapper.mapType(param_type);
        }

        // map return type - if function has error domain, return type is Result<T, E>
        const return_type = if (func_info.error_domain != null) blk: {
            // function returns Result type: {tag: i8, ok_value: T, error_code: i64}
            const ok_type = try self.type_mapper.mapType(func_info.return_type);
            break :blk self.createResultType(ok_type);
        } else try self.type_mapper.mapType(func_info.return_type);

        // create function type
        const func_type = llvm.functionType(
            return_type,
            param_types.ptr,
            @intCast(param_types.len),
            0,
        );

        // add function to module
        const func_name_z = try self.allocator.dupeZ(u8, func_decl.name);
        defer self.allocator.free(func_name_z);

        const func = llvm.addFunction(self.module, func_name_z.ptr, func_type);
        try self.functions.put(func_decl.name, func);
    }

    fn generateFunction(self: *LLVMBackend, func_decl: ast.FunctionDecl) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FunctionNotDeclared, SymbolNotFound, NotAFunction, FieldNotFound }!void {
        const func = self.functions.get(func_decl.name) orelse return error.FunctionNotDeclared;

        const symbol = self.symbols.global_scope.symbols.get(func_decl.name) orelse return error.SymbolNotFound;
        if (symbol != .function) return error.NotAFunction;

        // check if this is main and we have an init function to call
        const is_main = std.mem.eql(u8, func_decl.name, "main");
        const has_init = self.functions.contains("__ferrule_init");

        self.current_function = func;
        self.current_function_decl = func_decl;
        self.current_function_type = types.ResolvedType{ .function_type = .{
            .params = symbol.function.params,
            .return_type = try self.allocator.create(types.ResolvedType),
            .effects = symbol.function.effects,
            .error_domain = symbol.function.error_domain,
            .type_params = symbol.function.type_params,
        } };
        defer {
            if (self.current_function_type) |ft| {
                if (ft == .function_type) {
                    self.allocator.destroy(ft.function_type.return_type);
                }
            }
            self.current_function_type = null;
            self.current_function_decl = null;
        }

        if (self.current_function_type) |*ft| {
            if (ft.* == .function_type) {
                ft.function_type.return_type.* = symbol.function.return_type;
            }
        }

        // create entry block
        const entry_name = try self.allocator.dupeZ(u8, "entry");
        defer self.allocator.free(entry_name);

        const entry_block = llvm.appendBasicBlock(self.context, func, entry_name.ptr);
        llvm.positionBuilderAtEnd(self.builder, entry_block);

        // if this is main and we have an init function, call it first
        if (is_main and has_init) {
            const init_func = self.functions.get("__ferrule_init").?;
            const void_type = llvm.voidType(self.context);
            var init_params = [_]*llvm.TypeRef{};
            const init_func_type = llvm.functionType(void_type, &init_params, 0, 0);
            var empty_args = [_]*llvm.ValueRef{};
            _ = llvm.buildCall(self.builder, init_func_type, init_func, &empty_args, 0, "\x00");
        }

        // clear named values for new function scope
        self.named_values.clearRetainingCapacity();

        // types are arena-managed, no deinit needed
        self.named_types.clearRetainingCapacity();

        // add function parameters to named values
        // allocate space for params so they can be mutable
        for (func_decl.params, 0..) |param, i| {
            const param_val = llvm.getParam(func, @intCast(i));
            const param_type = symbol.function.params[i];
            const llvm_type = try self.type_mapper.mapType(param_type);

            const param_name_z = try self.allocator.dupeZ(u8, param.name);
            defer self.allocator.free(param_name_z);

            const alloca = llvm.buildAlloca(self.builder, llvm_type, param_name_z.ptr);
            _ = llvm.buildStore(self.builder, param_val, alloca);

            try self.named_values.put(param.name, alloca);
            // types are arena-managed via compilation context, no clone needed
            try self.named_types.put(param.name, param_type);
        }

        // generate function body
        for (func_decl.body) |stmt| {
            try self.generateStatement(stmt);
        }

        // if no explicit return and return type is void, add return void
        const ret_type = symbol.function.return_type;
        if (ret_type == .unit_type) {
            _ = llvm.buildRetVoid(self.builder);
        }

        self.current_function = null;
    }

    fn generateStatement(self: *LLVMBackend, stmt: ast.Stmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FieldNotFound }!void {
        switch (stmt) {
            .const_decl => |const_decl| {
                const var_type = try self.inferExpressionType(const_decl.value);

                if (const_decl.value.* == .array_literal) {
                    const value_ptr = try self.generateExpression(const_decl.value);
                    try self.named_values.put(const_decl.name, value_ptr);
                    try self.named_types.put(const_decl.name, var_type);
                } else {
                    const value = try self.generateExpression(const_decl.value);
                    const llvm_type = try self.type_mapper.mapType(var_type);

                    const var_name_z = try self.allocator.dupeZ(u8, const_decl.name);
                    defer self.allocator.free(var_name_z);

                    const alloca = llvm.buildAlloca(self.builder, llvm_type, var_name_z.ptr);
                    _ = llvm.buildStore(self.builder, value, alloca);

                    try self.named_values.put(const_decl.name, alloca);
                    try self.named_types.put(const_decl.name, var_type);
                }
            },

            .var_decl => |var_decl| {
                const value = try self.generateExpression(var_decl.value);

                const var_type = try self.inferExpressionType(var_decl.value);
                const llvm_type = try self.type_mapper.mapType(var_type);

                const var_name_z = try self.allocator.dupeZ(u8, var_decl.name);
                defer self.allocator.free(var_name_z);

                const alloca = llvm.buildAlloca(self.builder, llvm_type, var_name_z.ptr);
                _ = llvm.buildStore(self.builder, value, alloca);

                try self.named_values.put(var_decl.name, alloca);
                try self.named_types.put(var_decl.name, var_type);
            },

            .return_stmt => |ret_stmt| {
                if (ret_stmt.value) |value| {
                    const ret_val = try self.generateExpression(value);
                    _ = llvm.buildRet(self.builder, ret_val);
                } else {
                    _ = llvm.buildRetVoid(self.builder);
                }
            },

            .expr_stmt => |expr| {
                _ = try self.generateExpression(expr);
            },

            .if_stmt => |if_stmt| {
                try self.generateIfStatement(if_stmt);
            },

            .while_stmt => |while_stmt| {
                try self.generateWhileStatement(while_stmt);
            },

            .assign_stmt => |assign_stmt| {
                const value = try self.generateExpression(assign_stmt.value);
                const target_ptr = self.named_values.get(assign_stmt.target.name) orelse return error.UndefinedVariable;
                _ = llvm.buildStore(self.builder, value, target_ptr);
            },

            .package_decl => {
                // package declarations are metadata, no codegen needed
            },

            .domain_decl => {
                // domain declarations are for error handling, will implement later
            },

            .use_error => {
                // use error declarations are metadata, no codegen needed
            },

            .type_decl => {
                // type declarations might need codegen for runtime reflection
                // but for now, skip
            },

            .error_decl => {
                // error declarations define error types, skip for now
            },

            .import_decl => {
                // import declarations are handled by linker
            },

            .break_stmt => {
                // break statement for loops
                return error.StatementNotImplemented;
            },

            .continue_stmt => {
                // continue statement for loops
                return error.StatementNotImplemented;
            },

            .defer_stmt => {
                // defer statement for cleanup
                return error.StatementNotImplemented;
            },

            .for_stmt => |for_stmt| {
                try self.generateForStatement(for_stmt);
            },

            .match_stmt => {
                // pattern matching
                return error.StatementNotImplemented;
            },

            .function_decl => {
                // function declarations at statement level (nested functions)
                return error.StatementNotImplemented;
            },
        }
    }

    fn generateExpression(self: *LLVMBackend, expr: *ast.Expr) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, NoCurrentFunction, FieldNotFound, StatementNotImplemented, NoElseBlock }!*llvm.ValueRef {
        switch (expr.*) {
            .number => |num_str| {
                // try to parse as integer first, then float
                if (std.fmt.parseInt(i64, num_str, 10)) |val| {
                    const int_type = llvm.int32Type(self.context);
                    return llvm.constInt(int_type, @intCast(val), 1);
                } else |_| {
                    if (std.fmt.parseFloat(f64, num_str)) |val| {
                        const float_type = llvm.doubleType(self.context);
                        return llvm.constReal(float_type, val);
                    } else |_| {
                        return error.InvalidNumber;
                    }
                }
            },

            .string => |str| {
                // strip quotes from string literal
                const actual_str = if (str.len >= 2 and str[0] == '"' and str[str.len - 1] == '"')
                    str[1 .. str.len - 1]
                else
                    str;

                // create global string constant
                const global_name = try std.fmt.allocPrint(self.allocator, ".str.{d}", .{@intFromPtr(actual_str.ptr)});
                defer self.allocator.free(global_name);
                const global_name_z = try self.allocator.dupeZ(u8, global_name);
                defer self.allocator.free(global_name_z);

                const str_z = try self.allocator.dupeZ(u8, actual_str);
                defer self.allocator.free(str_z);

                const str_type = llvm.arrayType(llvm.int8Type(self.context), @intCast(actual_str.len + 1));
                const global = llvm.addGlobal(self.module, str_type, global_name_z.ptr);
                const str_const = llvm.constString(self.context, str_z.ptr, @intCast(actual_str.len), 0);
                llvm.setInitializer(global, str_const);
                llvm.setGlobalConstant(global, 1);

                // return string struct { ptr, len }
                const ptr_val = llvm.constPointerCast(global, llvm.pointerType(llvm.int8Type(self.context), 0));
                const len_val = llvm.constInt(llvm.int64Type(self.context), actual_str.len, 0);

                const fields = [_]*llvm.ValueRef{ ptr_val, len_val };
                return llvm.constStruct(self.context, &fields, 2, 0);
            },

            .identifier => |ident| {
                const var_ptr = self.named_values.get(ident.name) orelse return error.UndefinedVariable;

                // infer type to load correctly
                // types are arena-managed, no deinit needed
                const var_type = try self.inferExpressionType(expr);
                const llvm_type = try self.type_mapper.mapType(var_type);

                const load_name = try self.allocator.dupeZ(u8, ident.name);
                defer self.allocator.free(load_name);

                return llvm.buildLoad(self.builder, llvm_type, var_ptr, load_name.ptr);
            },

            .unary => |un_op| {
                const operand = try self.generateExpression(un_op.operand);
                const result_name = "unop\x00";

                return switch (un_op.op) {
                    .negate => {
                        const zero = llvm.constInt(llvm.int32Type(self.context), 0, 0);
                        return llvm.buildSub(self.builder, zero, operand, result_name);
                    },
                    .not => {
                        const zero = llvm.constInt(llvm.int1Type(self.context), 0, 0);
                        return llvm.buildICmp(self.builder, .eq, operand, zero, result_name);
                    },
                    .bitwise_not => return error.OperationNotImplemented,
                };
            },

            .binary => |bin_op| {
                var lhs = try self.generateExpression(bin_op.left);
                var rhs = try self.generateExpression(bin_op.right);

                const result_name = "binop\x00";
                const cmp_name = "cmp\x00";

                // for comparisons, ensure both operands have the same type
                // cast smaller int to larger int if needed
                const lhs_type = llvm.typeOf(lhs);
                const rhs_type = llvm.typeOf(rhs);
                if (lhs_type != rhs_type) {
                    const lhs_kind = llvm.getTypeKind(lhs_type);
                    const rhs_kind = llvm.getTypeKind(rhs_type);
                    if (lhs_kind == .integer and rhs_kind == .integer) {
                        const lhs_bits = llvm.getIntTypeWidth(lhs_type);
                        const rhs_bits = llvm.getIntTypeWidth(rhs_type);
                        if (lhs_bits < rhs_bits) {
                            // extend lhs to match rhs
                            lhs = llvm.buildSExt(self.builder, lhs, rhs_type, "sext\x00");
                        } else if (rhs_bits < lhs_bits) {
                            // extend rhs to match lhs
                            rhs = llvm.buildSExt(self.builder, rhs, lhs_type, "sext\x00");
                        }
                    }
                }

                return switch (bin_op.op) {
                    .add => llvm.buildAdd(self.builder, lhs, rhs, result_name),
                    .subtract => llvm.buildSub(self.builder, lhs, rhs, result_name),
                    .multiply => llvm.buildMul(self.builder, lhs, rhs, result_name),
                    .divide => llvm.buildSDiv(self.builder, lhs, rhs, result_name),
                    .modulo => llvm.buildSRem(self.builder, lhs, rhs, result_name),
                    .eq => llvm.buildICmp(self.builder, .eq, lhs, rhs, cmp_name),
                    .ne => llvm.buildICmp(self.builder, .ne, lhs, rhs, cmp_name),
                    .lt => llvm.buildICmp(self.builder, .slt, lhs, rhs, cmp_name),
                    .gt => llvm.buildICmp(self.builder, .sgt, lhs, rhs, cmp_name),
                    .le => llvm.buildICmp(self.builder, .sle, lhs, rhs, cmp_name),
                    .ge => llvm.buildICmp(self.builder, .sge, lhs, rhs, cmp_name),
                    .logical_and => llvm.buildAnd(self.builder, lhs, rhs, result_name),
                    .logical_or => llvm.buildOr(self.builder, lhs, rhs, result_name),
                    .bitwise_and => llvm.buildAnd(self.builder, lhs, rhs, result_name),
                    .bitwise_or => llvm.buildOr(self.builder, lhs, rhs, result_name),
                    .bitwise_xor => llvm.buildXor(self.builder, lhs, rhs, result_name),
                    else => error.OperationNotImplemented,
                };
            },

            .bool_literal => |val| {
                const bool_type = llvm.int1Type(self.context);
                return llvm.constInt(bool_type, if (val) 1 else 0, 0);
            },

            .array_literal => |al| {
                if (al.elements.len == 0) {
                    return error.ExpressionNotImplemented;
                }

                const elem_type_resolved = try self.inferExpressionType(al.elements[0]);
                const elem_type = try self.type_mapper.mapType(elem_type_resolved);
                const array_type = llvm.arrayType(elem_type, @intCast(al.elements.len));

                const element_values = try self.allocator.alloc(*llvm.ValueRef, al.elements.len);
                defer self.allocator.free(element_values);

                for (al.elements, 0..) |elem, i| {
                    element_values[i] = try self.generateExpression(elem);
                }

                const array_alloca = llvm.buildAlloca(self.builder, array_type, "array\x00");

                for (element_values, 0..) |val, i| {
                    const i32_type = llvm.int32Type(self.context);
                    const indices = [_]*llvm.ValueRef{ llvm.constInt(i32_type, 0, 0), llvm.constInt(i32_type, @intCast(i), 0) };
                    const elem_ptr = llvm.buildGEP(self.builder, array_type, array_alloca, &indices, 2, "elem.ptr\x00");
                    _ = llvm.buildStore(self.builder, val, elem_ptr);
                }

                return array_alloca;
            },

            .call => |call| {
                // callee must be an identifier for now
                if (call.callee.* != .identifier) return error.ExpressionNotImplemented;
                const func_name = call.callee.identifier.name;

                // Check if this is a builtin function call
                if (symbol_table.SymbolTable.isBuiltin(func_name)) {
                    return try self.generateBuiltinCall(func_name, call.args);
                }

                const func = self.functions.get(func_name) orelse return error.FunctionNotFound;

                const args = try self.allocator.alloc(*llvm.ValueRef, call.args.len);
                defer self.allocator.free(args);

                for (call.args, 0..) |arg, i| {
                    args[i] = try self.generateExpression(arg);
                }

                const symbol = self.symbols.global_scope.symbols.get(func_name) orelse return error.FunctionNotFound;
                if (symbol != .function) return error.FunctionNotFound;

                // build the function type
                const param_types = try self.allocator.alloc(*llvm.TypeRef, symbol.function.params.len);
                defer self.allocator.free(param_types);

                for (symbol.function.params, 0..) |param_type, i| {
                    param_types[i] = try self.type_mapper.mapType(param_type);
                }

                // if function has error domain, return type is Result<T, E>
                const ret_type = if (symbol.function.error_domain != null) blk: {
                    const ok_type = try self.type_mapper.mapType(symbol.function.return_type);
                    break :blk self.createResultType(ok_type);
                } else try self.type_mapper.mapType(symbol.function.return_type);
                const func_type = llvm.functionType(ret_type, param_types.ptr, @intCast(param_types.len), 0);

                const call_name = "call\x00";
                return llvm.buildCall(self.builder, func_type, func, args.ptr, @intCast(args.len), call_name);
            },

            .ok => |ok_expr| {
                return try self.generateOkExpr(ok_expr);
            },

            .err => |err_expr| {
                return try self.generateErrExpr(err_expr);
            },

            .check => |check_expr| {
                return try self.generateCheckExpr(check_expr);
            },

            .ensure => |ensure_expr| {
                return try self.generateEnsureExpr(ensure_expr);
            },

            .map_error => |map_error_expr| {
                return try self.generateMapErrorExpr(map_error_expr);
            },

            .record_literal => |rl| {
                return try self.generateRecordLiteral(rl);
            },

            .field_access => |fa| {
                return try self.generateFieldAccess(fa);
            },

            .null_literal => {
                return try self.generateNullLiteral(expr);
            },

            .match_expr => |me| {
                return try self.generateMatchExpr(me);
            },

            .variant_constructor => |vc| {
                return try self.generateVariantConstructor(vc);
            },

            .block_expr => |be| {
                return try self.generateBlockExpr(be);
            },

            else => return error.ExpressionNotImplemented,
        }
    }

    /// generate block expression - executes statements and returns result expression value
    fn generateBlockExpr(self: *LLVMBackend, block_expr: ast.BlockExpr) !*llvm.ValueRef {
        // generate each statement in the block
        for (block_expr.statements) |stmt| {
            try self.generateStatement(stmt);
        }

        // generate and return the result expression if present
        if (block_expr.result_expr) |result| {
            return try self.generateExpression(result);
        }

        // no result expression - return unit (void represented as i32 0)
        return llvm.constInt(llvm.int32Type(self.context), 0, 0);
    }

    /// generate match expression - creates switch or if-else chain based on pattern types
    fn generateMatchExpr(self: *LLVMBackend, match_expr: ast.MatchExpr) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, NoCurrentFunction, FieldNotFound, StatementNotImplemented, NoElseBlock }!*llvm.ValueRef {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        // generate the value being matched
        const match_value = try self.generateExpression(match_expr.value);

        // infer result type - try multiple arms since some may have pattern bindings
        // that aren't in named_types yet
        const result_type_resolved: types.ResolvedType = blk: {
            for (match_expr.arms) |arm| {
                if (self.inferExpressionType(arm.body)) |arm_type| {
                    break :blk arm_type;
                } else |_| {
                    continue;
                }
            }
            break :blk types.ResolvedType.unit_type;
        };
        // types are arena-managed, no deinit needed
        const result_type = try self.type_mapper.mapType(result_type_resolved);

        // create merge block for phi
        const merge_block = llvm.appendBasicBlock(self.context, current_func, "match.merge\x00");

        // track arm values and blocks for phi
        var arm_values = try self.allocator.alloc(*llvm.ValueRef, match_expr.arms.len);
        defer self.allocator.free(arm_values);
        var arm_blocks = try self.allocator.alloc(*llvm.BasicBlockRef, match_expr.arms.len);
        defer self.allocator.free(arm_blocks);

        const value_type = llvm.typeOf(match_value);
        const type_kind = llvm.getTypeKind(value_type);

        if (type_kind == .integer) {
            // count non-wildcard cases for switch
            var case_count: u32 = 0;
            var default_arm_idx: ?usize = null;
            for (match_expr.arms, 0..) |arm, i| {
                switch (arm.pattern) {
                    .number => case_count += 1,
                    .wildcard, .identifier => default_arm_idx = i,
                    else => {},
                }
            }

            // create default block
            const default_block = llvm.appendBasicBlock(self.context, current_func, "match.default\x00");
            const switch_inst = llvm.buildSwitch(self.builder, match_value, default_block, case_count);

            // generate each arm
            for (match_expr.arms, 0..) |arm, i| {
                switch (arm.pattern) {
                    .number => |num_str| {
                        const case_block = llvm.appendBasicBlock(self.context, current_func, "match.case\x00");
                        const case_val = if (std.fmt.parseInt(i64, num_str, 10)) |val|
                            llvm.constInt(value_type, @intCast(val), 1)
                        else |_|
                            llvm.constInt(value_type, 0, 0);
                        llvm.addCase(switch_inst, case_val, case_block);

                        llvm.positionBuilderAtEnd(self.builder, case_block);
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .wildcard, .identifier => {
                        // handled by default block
                        llvm.positionBuilderAtEnd(self.builder, default_block);
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    else => {
                        // for unsupported patterns, generate in default block
                        llvm.positionBuilderAtEnd(self.builder, default_block);
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                }
            }

            // if no default arm was set, add unreachable to default block
            if (default_arm_idx == null) {
                llvm.positionBuilderAtEnd(self.builder, default_block);
                _ = llvm.buildUnreachable(self.builder);
            }
        } else {
            // for non-integer types (like Result), generate if-else chain
            var next_block: ?*llvm.BasicBlockRef = llvm.appendBasicBlock(self.context, current_func, "match.arm0\x00");
            _ = llvm.buildBr(self.builder, next_block.?);

            // create unreachable block for non-exhaustive match fallthrough
            const unreachable_block = llvm.appendBasicBlock(self.context, current_func, "match.unreachable\x00");

            for (match_expr.arms, 0..) |arm, i| {
                llvm.positionBuilderAtEnd(self.builder, next_block.?);

                const is_last = i == match_expr.arms.len - 1;
                next_block = if (!is_last) llvm.appendBasicBlock(self.context, current_func, "match.arm\x00") else null;
                // for last arm's fallback, use unreachable block (not merge) to avoid PHI issues
                const fallback_block = next_block orelse unreachable_block;

                switch (arm.pattern) {
                    .ok_pattern => |ok_pat| {
                        // check if result.tag == 0
                        const tag = llvm.buildExtractValue(self.builder, match_value, 0, "match.tag\x00");
                        const is_ok = llvm.buildICmp(self.builder, .eq, tag, llvm.constInt(llvm.int8Type(self.context), 0, 0), "is_ok\x00");

                        const ok_block = llvm.appendBasicBlock(self.context, current_func, "match.ok\x00");
                        _ = llvm.buildCondBr(self.builder, is_ok, ok_block, fallback_block);

                        llvm.positionBuilderAtEnd(self.builder, ok_block);

                        // bind the ok value if there's a binding name
                        if (ok_pat.binding) |binding_name| {
                            const ok_value = llvm.buildExtractValue(self.builder, match_value, 1, "ok.value\x00");
                            try self.named_values.put(binding_name, ok_value);
                        }

                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .err_pattern => |err_pat| {
                        // check if result.tag == 1
                        const tag = llvm.buildExtractValue(self.builder, match_value, 0, "match.tag\x00");
                        const is_err = llvm.buildICmp(self.builder, .eq, tag, llvm.constInt(llvm.int8Type(self.context), 1, 0), "is_err\x00");

                        const err_block = llvm.appendBasicBlock(self.context, current_func, "match.err\x00");
                        _ = llvm.buildCondBr(self.builder, is_err, err_block, fallback_block);

                        llvm.positionBuilderAtEnd(self.builder, err_block);

                        // bind error fields if present
                        if (err_pat.fields) |fields| {
                            const err_value = llvm.buildExtractValue(self.builder, match_value, 2, "err.value\x00");
                            for (fields) |field| {
                                // for now, bind the error code as the field value
                                try self.named_values.put(field.name, err_value);
                            }
                        }

                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .variant => |v| {
                        // union variant pattern - check tag and extract fields
                        // union is represented as {tag: i8, payload: i64}
                        const tag = llvm.buildExtractValue(self.builder, match_value, 0, "match.variant.tag\x00");

                        // compute variant index by finding it in the match expression's type
                        const variant_idx = self.findVariantIndex(match_expr.value, v.name) orelse 0;

                        const expected_tag = llvm.constInt(llvm.int8Type(self.context), variant_idx, 0);
                        const is_variant = llvm.buildICmp(self.builder, .eq, tag, expected_tag, "is_variant\x00");

                        const variant_block = llvm.appendBasicBlock(self.context, current_func, "match.variant\x00");
                        _ = llvm.buildCondBr(self.builder, is_variant, variant_block, fallback_block);

                        llvm.positionBuilderAtEnd(self.builder, variant_block);

                        // bind variant fields if present
                        if (v.fields) |fields| {
                            const payload = llvm.buildExtractValue(self.builder, match_value, 1, "variant.payload\x00");

                            // get the field types from the variant definition
                            // types are arena-managed, no cleanup needed
                            const field_types = self.getVariantFieldTypes(match_expr.value, v.name);

                            for (fields, 0..) |field, field_idx| {
                                // get the field type to properly extract the payload
                                var field_llvm_type = llvm.int64Type(self.context); // default
                                if (field_types) |ft| {
                                    if (field_idx < ft.len) {
                                        field_llvm_type = self.type_mapper.mapType(ft[field_idx]) catch llvm.int64Type(self.context);
                                    }
                                }

                                // use memory-based type punning for extracting field value:
                                // 1. allocate space for i64 (the payload type)
                                // 2. store the i64 payload
                                // 3. bitcast pointer to target type pointer
                                // 4. load as target type
                                const payload_alloca = llvm.buildAlloca(self.builder, llvm.int64Type(self.context), "payload.tmp\x00");
                                _ = llvm.buildStore(self.builder, payload, payload_alloca);

                                // cast the pointer to point to the target type
                                const casted_ptr = llvm.buildBitCast(self.builder, payload_alloca, llvm.pointerType(field_llvm_type, 0), "field.ptr\x00");

                                // load as the target type
                                const field_name_z = self.allocator.dupeZ(u8, field.name) catch continue;
                                defer self.allocator.free(field_name_z);

                                const field_value = llvm.buildLoad(self.builder, field_llvm_type, casted_ptr, field_name_z.ptr);

                                // allocate space for the named variable
                                const alloca = llvm.buildAlloca(self.builder, field_llvm_type, field_name_z.ptr);
                                _ = llvm.buildStore(self.builder, field_value, alloca);

                                try self.named_values.put(field.name, alloca);

                                // also register the type so inferExpressionType works
                                // types are arena-managed, no clone needed
                                if (field_types) |ft| {
                                    if (field_idx < ft.len) {
                                        try self.named_types.put(field.name, ft[field_idx]);
                                    }
                                }
                            }
                        }

                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .some_pattern => |some_pat| {
                        // nullable type: check if has_value == true
                        const has_value = llvm.buildExtractValue(self.builder, match_value, 0, "match.has_value\x00");
                        const is_some = llvm.buildICmp(self.builder, .ne, has_value, llvm.constInt(llvm.int1Type(self.context), 0, 0), "is_some\x00");

                        const some_block = llvm.appendBasicBlock(self.context, current_func, "match.some\x00");
                        _ = llvm.buildCondBr(self.builder, is_some, some_block, fallback_block);

                        llvm.positionBuilderAtEnd(self.builder, some_block);

                        // bind the inner value if there's a binding name
                        if (some_pat.binding) |binding_name| {
                            const inner_value = llvm.buildExtractValue(self.builder, match_value, 1, "some.value\x00");
                            try self.named_values.put(binding_name, inner_value);
                        }

                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .none_pattern => {
                        // nullable type: check if has_value == false
                        const has_value = llvm.buildExtractValue(self.builder, match_value, 0, "match.has_value\x00");
                        const is_none = llvm.buildICmp(self.builder, .eq, has_value, llvm.constInt(llvm.int1Type(self.context), 0, 0), "is_none\x00");

                        const none_block = llvm.appendBasicBlock(self.context, current_func, "match.none\x00");
                        _ = llvm.buildCondBr(self.builder, is_none, none_block, fallback_block);

                        llvm.positionBuilderAtEnd(self.builder, none_block);
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    .wildcard, .identifier => {
                        // wildcard matches everything
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                    else => {
                        // fallback: evaluate arm body unconditionally
                        arm_values[i] = try self.generateExpression(arm.body);
                        arm_blocks[i] = llvm.getInsertBlock(self.builder);
                        _ = llvm.buildBr(self.builder, merge_block);
                    },
                }
            }

            // add unreachable instruction to the unreachable block
            llvm.positionBuilderAtEnd(self.builder, unreachable_block);
            _ = llvm.buildUnreachable(self.builder);
        }

        // merge block with phi
        llvm.positionBuilderAtEnd(self.builder, merge_block);
        const phi = llvm.buildPhi(self.builder, result_type, "match.result\x00");
        llvm.addIncoming(phi, arm_values.ptr, arm_blocks.ptr, @intCast(match_expr.arms.len));

        return phi;
    }

    /// generates a variant constructor expression like `Just { value: 42 }` or `Nothing`
    /// union is represented as {tag: i8, payload: i64}
    fn generateVariantConstructor(self: *LLVMBackend, variant_ctor: ast.VariantConstructorExpr) !*llvm.ValueRef {
        // find the variant index by looking up the union type in symbol table
        const tag: u64 = blk: {
            var iter = self.symbols.global_scope.symbols.iterator();
            while (iter.next()) |entry| {
                const symbol = entry.value_ptr.*;
                if (symbol == .type_def) {
                    const type_def = symbol.type_def;
                    if (type_def.underlying == .union_type) {
                        for (type_def.underlying.union_type.variants, 0..) |variant, idx| {
                            if (std.mem.eql(u8, variant.name, variant_ctor.variant_name)) {
                                break :blk idx;
                            }
                        }
                    }
                }
            }
            // fallback: use 0 if not found
            break :blk 0;
        };

        const i8_type = llvm.int8Type(self.context);
        const i64_type = llvm.int64Type(self.context);

        // create the union struct type
        const fields = [_]*llvm.TypeRef{ i8_type, i64_type };
        const union_type = llvm.structTypeInContext(self.context, &fields, 2, 0);

        // create the struct value
        var result = llvm.getUndef(union_type);
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i8_type, tag, 0), 0, "variant.tag\x00");

        // if there are fields, generate the payload
        if (variant_ctor.fields) |ctor_fields| {
            if (ctor_fields.len > 0) {
                // for simplicity, just use the first field's value as payload
                const first_field_value = try self.generateExpression(ctor_fields[0].value);
                // convert to i64 based on the type
                const value_type = llvm.typeOf(first_field_value);
                const type_kind = llvm.getTypeKind(value_type);

                const payload = switch (type_kind) {
                    .integer => blk: {
                        // sign extend integer to i64
                        const width = llvm.getIntTypeWidth(value_type);
                        if (width < 64) {
                            break :blk llvm.buildSExt(self.builder, first_field_value, i64_type, "variant.payload\x00");
                        } else {
                            break :blk first_field_value;
                        }
                    },
                    .double, .float => blk: {
                        // bitcast float/double to i64 via memory
                        const tmp_alloca = llvm.buildAlloca(self.builder, value_type, "float.tmp\x00");
                        _ = llvm.buildStore(self.builder, first_field_value, tmp_alloca);
                        const casted_ptr = llvm.buildBitCast(self.builder, tmp_alloca, llvm.pointerType(i64_type, 0), "int.ptr\x00");
                        break :blk llvm.buildLoad(self.builder, i64_type, casted_ptr, "variant.payload\x00");
                    },
                    else => blk: {
                        // for other types (structs, pointers), use zero placeholder
                        break :blk llvm.constInt(i64_type, 0, 0);
                    },
                };

                result = llvm.buildInsertValue(self.builder, result, payload, 1, "variant.value\x00");
            }
        } else {
            // no fields - set payload to 0
            result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i64_type, 0, 0), 1, "variant.value\x00");
        }

        return result;
    }

    /// finds the index of a variant in a union type by looking up the matched expression's type
    fn findVariantIndex(self: *LLVMBackend, expr: *ast.Expr, variant_name: []const u8) ?u64 {
        // try to infer the type of the expression and find the variant index
        // types are arena-managed, no deinit needed
        const expr_type = self.inferExpressionType(expr) catch return null;

        // resolve to union type
        const union_type = switch (expr_type) {
            .union_type => expr_type,
            .named => |n| if (n.underlying.* == .union_type) n.underlying.* else return null,
            else => return null,
        };

        // find the variant index
        for (union_type.union_type.variants, 0..) |variant, idx| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                return idx;
            }
        }

        return null;
    }

    /// finds variant field types from a union type for pattern binding
    /// types are arena-managed, caller does not need to free
    fn getVariantFieldTypes(self: *LLVMBackend, expr: *ast.Expr, variant_name: []const u8) ?[]types.ResolvedType {
        // try to infer the type of the expression
        const expr_type = self.inferExpressionType(expr) catch return null;
        // types are arena-managed, no deinit needed

        // resolve to union type
        const union_type = switch (expr_type) {
            .union_type => expr_type,
            .named => |n| if (n.underlying.* == .union_type) n.underlying.* else return null,
            else => return null,
        };

        // find the variant and return its field types directly
        // types are arena-managed, no clone needed
        for (union_type.union_type.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                return variant.field_types;
            }
        }

        return null;
    }

    /// generate `ok value` - wraps value in Result with tag=0
    fn generateOkExpr(self: *LLVMBackend, ok_expr: *ast.Expr) !*llvm.ValueRef {
        const value = try self.generateExpression(ok_expr);

        // get the result type from current function
        const ok_type = llvm.typeOf(value);
        const result_type = self.createResultType(ok_type);

        // create result struct: {tag=0, value, error_code=0}
        const i8_type = llvm.int8Type(self.context);
        const i64_type = llvm.int64Type(self.context);

        var result = llvm.getUndef(result_type);
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i8_type, 0, 0), 0, "result.tag\x00");
        result = llvm.buildInsertValue(self.builder, result, value, 1, "result.value\x00");
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i64_type, 0, 0), 2, "result.err\x00");

        return result;
    }

    /// generate `err Variant { fields }` - creates Result with tag=1
    fn generateErrExpr(self: *LLVMBackend, err_expr: ast.ErrorExpr) !*llvm.ValueRef {
        const i8_type = llvm.int8Type(self.context);
        const i64_type = llvm.int64Type(self.context);

        // for now, error code is a hash of the variant name
        var error_code: u64 = 0;
        for (err_expr.variant) |c| {
            error_code = error_code *% 31 +% c;
        }

        // get the return type from current function to determine result type
        var ok_type = llvm.int32Type(self.context); // default
        if (self.current_function_type) |ft| {
            if (ft == .function_type) {
                ok_type = try self.type_mapper.mapType(ft.function_type.return_type.*);
            }
        }

        const result_type = self.createResultType(ok_type);

        // create result struct: {tag=1, undef value, error_code}
        var result = llvm.getUndef(result_type);
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i8_type, 1, 0), 0, "result.tag\x00");
        // leave value as undef for error case
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i64_type, error_code, 0), 2, "result.err\x00");

        return result;
    }

    /// generate `check expr` or `check expr with { frames }` - unwrap Result or return error
    fn generateCheckExpr(self: *LLVMBackend, check_expr: ast.CheckExpr) !*llvm.ValueRef {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        // generate the expression that returns a Result
        const result_val = try self.generateExpression(check_expr.expr);

        const i8_type = llvm.int8Type(self.context);

        // extract tag
        const tag = llvm.buildExtractValue(self.builder, result_val, 0, "check.tag\x00");

        // compare tag == 0 (ok)
        const is_ok = llvm.buildICmp(self.builder, .eq, tag, llvm.constInt(i8_type, 0, 0), "check.is_ok\x00");

        // create blocks
        const ok_block = llvm.appendBasicBlock(self.context, current_func, "check.ok\x00");
        const err_block = llvm.appendBasicBlock(self.context, current_func, "check.err\x00");
        const continue_block = llvm.appendBasicBlock(self.context, current_func, "check.cont\x00");

        _ = llvm.buildCondBr(self.builder, is_ok, ok_block, err_block);

        // error block: propagate the error by returning it
        llvm.positionBuilderAtEnd(self.builder, err_block);

        // if there are context frames, allocate and populate them
        if (check_expr.context_frame) |frame_fields| {
            if (frame_fields.len > 0) {
                try self.generateContextFrame(frame_fields);
            }
        }

        // return the error result from the function
        _ = llvm.buildRet(self.builder, result_val);

        // ok block: extract the value and continue
        llvm.positionBuilderAtEnd(self.builder, ok_block);
        const value = llvm.buildExtractValue(self.builder, result_val, 1, "check.value\x00");
        _ = llvm.buildBr(self.builder, continue_block);

        // continue block
        llvm.positionBuilderAtEnd(self.builder, continue_block);

        // create phi node to get the value
        const value_type = llvm.typeOf(value);
        const phi = llvm.buildPhi(self.builder, value_type, "check.result\x00");
        var incoming_values = [_]*llvm.ValueRef{value};
        var incoming_blocks = [_]*llvm.BasicBlockRef{ok_block};
        llvm.addIncoming(phi, &incoming_values, &incoming_blocks, 1);

        return phi;
    }

    /// generate `ensure condition else err Variant { fields }` - guard pattern
    fn generateEnsureExpr(self: *LLVMBackend, ensure_expr: ast.EnsureExpr) !*llvm.ValueRef {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        // generate the condition
        const condition = try self.generateExpression(ensure_expr.condition);

        // create blocks
        const ok_block = llvm.appendBasicBlock(self.context, current_func, "ensure.ok\x00");
        const err_block = llvm.appendBasicBlock(self.context, current_func, "ensure.err\x00");
        const continue_block = llvm.appendBasicBlock(self.context, current_func, "ensure.cont\x00");

        _ = llvm.buildCondBr(self.builder, condition, ok_block, err_block);

        // error block: return the error
        llvm.positionBuilderAtEnd(self.builder, err_block);
        const err_result = try self.generateErrExpr(ensure_expr.error_expr);
        _ = llvm.buildRet(self.builder, err_result);

        // ok block: continue
        llvm.positionBuilderAtEnd(self.builder, ok_block);
        _ = llvm.buildBr(self.builder, continue_block);

        // continue block
        llvm.positionBuilderAtEnd(self.builder, continue_block);

        // ensure returns Unit (void), so return an i32 0 as placeholder
        return llvm.constInt(llvm.int32Type(self.context), 0, 0);
    }

    /// generate `map_error expr using (e => transform)` - adapt error domains
    fn generateMapErrorExpr(self: *LLVMBackend, map_error_expr: ast.MapErrorExpr) !*llvm.ValueRef {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        // generate the expression that returns a Result
        const result_val = try self.generateExpression(map_error_expr.expr);

        const i8_type = llvm.int8Type(self.context);

        // extract tag
        const tag = llvm.buildExtractValue(self.builder, result_val, 0, "map_err.tag\x00");

        // compare tag == 0 (ok)
        const is_ok = llvm.buildICmp(self.builder, .eq, tag, llvm.constInt(i8_type, 0, 0), "map_err.is_ok\x00");

        // create blocks
        const ok_block = llvm.appendBasicBlock(self.context, current_func, "map_err.ok\x00");
        const err_block = llvm.appendBasicBlock(self.context, current_func, "map_err.err\x00");
        const merge_block = llvm.appendBasicBlock(self.context, current_func, "map_err.merge\x00");

        _ = llvm.buildCondBr(self.builder, is_ok, ok_block, err_block);

        // ok block: pass through the ok value
        llvm.positionBuilderAtEnd(self.builder, ok_block);
        _ = llvm.buildBr(self.builder, merge_block);

        // err block: transform the error (for now, just pass through)
        // full implementation would evaluate the transform expression
        llvm.positionBuilderAtEnd(self.builder, err_block);
        _ = llvm.buildBr(self.builder, merge_block);

        // merge block
        llvm.positionBuilderAtEnd(self.builder, merge_block);

        // create phi for the result
        const result_type = llvm.typeOf(result_val);
        const phi = llvm.buildPhi(self.builder, result_type, "map_err.result\x00");
        var incoming_values = [_]*llvm.ValueRef{ result_val, result_val };
        var incoming_blocks = [_]*llvm.BasicBlockRef{ ok_block, err_block };
        llvm.addIncoming(phi, &incoming_values, &incoming_blocks, 2);

        return phi;
    }

    /// generate context frame for error propagation
    fn generateContextFrame(self: *LLVMBackend, frame_fields: []ast.FieldAssignment) !void {
        const frame_alloc = self.rt_frame_alloc orelse return;
        const frame_add_string = self.rt_frame_add_string orelse return;

        const i8_type = llvm.int8Type(self.context);
        const i8_ptr_type = llvm.pointerType(i8_type, 0);
        const i64_type = llvm.int64Type(self.context);
        const i1_type = llvm.int1Type(self.context);
        const void_type = llvm.voidType(self.context);

        // allocate a frame
        var empty_params = [_]*llvm.TypeRef{};
        const alloc_type = llvm.functionType(i8_ptr_type, &empty_params, 0, 0);
        var empty_args = [_]*llvm.ValueRef{};
        const frame_ptr = llvm.buildCall(self.builder, alloc_type, frame_alloc, &empty_args, 0, "frame\x00");

        // add each field to the frame
        for (frame_fields) |field| {
            // create global string for key
            const key_global = try self.createGlobalString(field.name);
            const key_len = llvm.constInt(i64_type, field.name.len, 0);

            // generate value expression
            const value_expr = try self.generateExpression(field.value);

            // if value is a string, add it directly
            // for simplicity, assume all context values are strings for now
            const value_ptr = llvm.buildExtractValue(self.builder, value_expr, 0, "ctx.val.ptr\x00");
            const value_len = llvm.buildExtractValue(self.builder, value_expr, 1, "ctx.val.len\x00");

            var add_params = [_]*llvm.TypeRef{ i8_ptr_type, i8_ptr_type, i64_type, i8_ptr_type, i64_type };
            const add_type = llvm.functionType(i1_type, &add_params, 5, 0);
            var add_args = [_]*llvm.ValueRef{ frame_ptr, key_global, key_len, value_ptr, value_len };
            _ = llvm.buildCall(self.builder, add_type, frame_add_string, &add_args, 5, "");
        }

        _ = void_type;
    }

    /// create a global string constant and return pointer to it
    fn createGlobalString(self: *LLVMBackend, str: []const u8) !*llvm.ValueRef {
        const i8_type = llvm.int8Type(self.context);

        const global_name = try std.fmt.allocPrint(self.allocator, ".str.ctx.{d}", .{@intFromPtr(str.ptr)});
        defer self.allocator.free(global_name);
        const global_name_z = try self.allocator.dupeZ(u8, global_name);
        defer self.allocator.free(global_name_z);

        const str_z = try self.allocator.dupeZ(u8, str);
        defer self.allocator.free(str_z);

        const str_type = llvm.arrayType(i8_type, @intCast(str.len + 1));
        const global = llvm.addGlobal(self.module, str_type, global_name_z.ptr);
        const str_const = llvm.constString(self.context, str_z.ptr, @intCast(str.len), 0);
        llvm.setInitializer(global, str_const);
        llvm.setGlobalConstant(global, 1);

        return llvm.constPointerCast(global, llvm.pointerType(i8_type, 0));
    }

    /// generate record literal { field1: value1, field2: value2, ... }
    fn generateRecordLiteral(self: *LLVMBackend, record_lit: ast.RecordLiteralExpr) !*llvm.ValueRef {
        const field_count = record_lit.fields.len;

        if (field_count == 0) {
            // empty record - return void/unit
            return llvm.getUndef(llvm.voidType(self.context));
        }

        // generate values for each field
        const field_values = try self.allocator.alloc(*llvm.ValueRef, field_count);
        defer self.allocator.free(field_values);

        const field_types = try self.allocator.alloc(*llvm.TypeRef, field_count);
        defer self.allocator.free(field_types);

        for (record_lit.fields, 0..) |field, i| {
            field_values[i] = try self.generateExpression(field.value);
            field_types[i] = llvm.typeOf(field_values[i]);
        }

        // create struct type for this record
        const struct_type = llvm.structTypeInContext(self.context, field_types.ptr, @intCast(field_count), 0);

        // build the struct value
        var result = llvm.getUndef(struct_type);
        for (field_values, 0..) |val, i| {
            result = llvm.buildInsertValue(self.builder, result, val, @intCast(i), "record.field\x00");
        }

        return result;
    }

    /// generate field access: object.field
    fn generateFieldAccess(self: *LLVMBackend, field_access: ast.FieldAccessExpr) !*llvm.ValueRef {
        const object = try self.generateExpression(field_access.object);
        const field_name = field_access.field;

        // determine field index based on object type
        // types are arena-managed, no deinit needed
        const object_type = try self.inferExpressionType(field_access.object);

        switch (object_type) {
            .record => |rec| {
                // find field index
                for (rec.field_names, 0..) |name, i| {
                    if (std.mem.eql(u8, name, field_name)) {
                        return llvm.buildExtractValue(self.builder, object, @intCast(i), "field\x00");
                    }
                }
                return error.FieldNotFound;
            },
            .result => {
                // result struct: {tag: i8, value: T, error_code: i64}
                if (std.mem.eql(u8, field_name, "tag")) {
                    return llvm.buildExtractValue(self.builder, object, 0, "result.tag\x00");
                } else if (std.mem.eql(u8, field_name, "value")) {
                    return llvm.buildExtractValue(self.builder, object, 1, "result.value\x00");
                } else if (std.mem.eql(u8, field_name, "error_code")) {
                    return llvm.buildExtractValue(self.builder, object, 2, "result.error_code\x00");
                }
                return error.FieldNotFound;
            },
            .nullable => {
                // nullable struct: {has_value: i1, value: T}
                if (std.mem.eql(u8, field_name, "has_value")) {
                    return llvm.buildExtractValue(self.builder, object, 0, "nullable.has_value\x00");
                } else if (std.mem.eql(u8, field_name, "value")) {
                    return llvm.buildExtractValue(self.builder, object, 1, "nullable.value\x00");
                }
                return error.FieldNotFound;
            },
            .string_type => {
                // string struct: {ptr, len}
                if (std.mem.eql(u8, field_name, "ptr")) {
                    return llvm.buildExtractValue(self.builder, object, 0, "string.ptr\x00");
                } else if (std.mem.eql(u8, field_name, "len")) {
                    return llvm.buildExtractValue(self.builder, object, 1, "string.len\x00");
                }
                return error.FieldNotFound;
            },
            .array => |arr| {
                if (std.mem.eql(u8, field_name, "len")) {
                    // return compile-time known length
                    return llvm.constInt(llvm.int64Type(self.context), arr.size, 0);
                }
                return error.FieldNotFound;
            },
            else => return error.FieldNotFound,
        }
    }

    /// generate null literal for Maybe/nullable types
    fn generateNullLiteral(self: *LLVMBackend, expr: *ast.Expr) !*llvm.ValueRef {
        // infer the expected nullable type from context
        // for now, create a generic nullable with has_value = false
        _ = expr;

        // create nullable struct with has_value = false
        const i1_type = llvm.int1Type(self.context);
        const i64_type = llvm.int64Type(self.context);

        // default to i64 as placeholder inner type
        const nullable_type = self.type_mapper.createNullableType(i64_type);

        var result = llvm.getUndef(nullable_type);
        result = llvm.buildInsertValue(self.builder, result, llvm.constInt(i1_type, 0, 0), 0, "null.has_value\x00");
        // leave value as undef

        return result;
    }

    /// create a Result type struct for the given ok type
    fn createResultType(self: *LLVMBackend, ok_type: *llvm.TypeRef) *llvm.TypeRef {
        const i8_type = llvm.int8Type(self.context);
        const i64_type = llvm.int64Type(self.context);

        const fields = [_]*llvm.TypeRef{
            i8_type, // tag: 0 = ok, 1 = err
            ok_type, // payload (ok value)
            i64_type, // error code
        };
        return llvm.structTypeInContext(self.context, &fields, 3, 0);
    }

    fn generateIfStatement(self: *LLVMBackend, if_stmt: ast.IfStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FieldNotFound }!void {
        const cond = try self.generateExpression(if_stmt.condition);

        const current_func = self.current_function orelse return error.NoCurrentFunction;

        const then_block = llvm.appendBasicBlock(self.context, current_func, "then\x00");
        const else_block = if (if_stmt.else_block != null)
            llvm.appendBasicBlock(self.context, current_func, "else\x00")
        else
            null;
        const merge_block = llvm.appendBasicBlock(self.context, current_func, "merge\x00");

        _ = llvm.buildCondBr(self.builder, cond, then_block, else_block orelse merge_block);

        // then block
        llvm.positionBuilderAtEnd(self.builder, then_block);
        for (if_stmt.then_block) |stmt| {
            try self.generateStatement(stmt);
        }
        const current_then_block = llvm.getInsertBlock(self.builder);
        const then_has_terminator = llvm.getBasicBlockTerminator(current_then_block) != null;
        if (!then_has_terminator) {
            _ = llvm.buildBr(self.builder, merge_block);
        }

        // else block
        var else_has_terminator = false;
        if (if_stmt.else_block) |else_blk| {
            const else_bb = else_block orelse return error.NoElseBlock;
            llvm.positionBuilderAtEnd(self.builder, else_bb);
            for (else_blk) |stmt| {
                try self.generateStatement(stmt);
            }
            const current_else_block = llvm.getInsertBlock(self.builder);
            else_has_terminator = llvm.getBasicBlockTerminator(current_else_block) != null;
            if (!else_has_terminator) {
                _ = llvm.buildBr(self.builder, merge_block);
            }
        }

        // only position at merge block if it has predecessors
        if (!then_has_terminator or !else_has_terminator) {
            llvm.positionBuilderAtEnd(self.builder, merge_block);
        } else {
            // both branches terminate, so merge block is unreachable
            llvm.deleteBasicBlock(merge_block);
        }
    }

    fn generateWhileStatement(self: *LLVMBackend, while_stmt: ast.WhileStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FieldNotFound }!void {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        const cond_block = llvm.appendBasicBlock(self.context, current_func, "while.cond\x00");
        const body_block = llvm.appendBasicBlock(self.context, current_func, "while.body\x00");
        const exit_block = llvm.appendBasicBlock(self.context, current_func, "while.exit\x00");

        _ = llvm.buildBr(self.builder, cond_block);

        // condition block
        llvm.positionBuilderAtEnd(self.builder, cond_block);
        const cond = try self.generateExpression(while_stmt.condition);
        _ = llvm.buildCondBr(self.builder, cond, body_block, exit_block);

        // body block
        llvm.positionBuilderAtEnd(self.builder, body_block);
        for (while_stmt.body) |stmt| {
            try self.generateStatement(stmt);
        }
        const current_block = llvm.getInsertBlock(self.builder);
        if (llvm.getBasicBlockTerminator(current_block) == null) {
            _ = llvm.buildBr(self.builder, cond_block);
        }

        // exit block
        llvm.positionBuilderAtEnd(self.builder, exit_block);
    }

    fn generateForStatement(self: *LLVMBackend, for_stmt: ast.ForStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FieldNotFound }!void {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

        if (for_stmt.iterable.* == .range) {
            try self.generateForRange(for_stmt);
            return;
        }

        try self.generateForArray(for_stmt, current_func);
    }

    fn generateForRange(self: *LLVMBackend, for_stmt: ast.ForStmt) !void {
        const current_func = self.current_function orelse return error.NoCurrentFunction;
        const range = for_stmt.iterable.range;

        const start_val = try self.generateExpression(range.start);
        const end_val = try self.generateExpression(range.end);

        const i32_type = llvm.int32Type(self.context);
        const iter_alloca = llvm.buildAlloca(self.builder, i32_type, "for.iter\x00");
        _ = llvm.buildStore(self.builder, start_val, iter_alloca);

        const cond_block = llvm.appendBasicBlock(self.context, current_func, "for.cond\x00");
        const body_block = llvm.appendBasicBlock(self.context, current_func, "for.body\x00");
        const exit_block = llvm.appendBasicBlock(self.context, current_func, "for.exit\x00");

        _ = llvm.buildBr(self.builder, cond_block);

        llvm.positionBuilderAtEnd(self.builder, cond_block);
        const iter_val = llvm.buildLoad(self.builder, i32_type, iter_alloca, "iter\x00");
        const cond = llvm.buildICmp(self.builder, .slt, iter_val, end_val, "for.cond\x00");
        _ = llvm.buildCondBr(self.builder, cond, body_block, exit_block);

        llvm.positionBuilderAtEnd(self.builder, body_block);

        const prev_iterator_value = self.named_values.get(for_stmt.iterator);
        const prev_iterator_type = self.named_types.get(for_stmt.iterator);
        try self.named_values.put(for_stmt.iterator, iter_alloca);
        try self.named_types.put(for_stmt.iterator, types.ResolvedType.i32);

        for (for_stmt.body) |stmt| {
            try self.generateStatement(stmt);
        }

        const current_block = llvm.getInsertBlock(self.builder);
        if (llvm.getBasicBlockTerminator(current_block) == null) {
            const current_iter = llvm.buildLoad(self.builder, i32_type, iter_alloca, "iter.cur\x00");
            const next_iter = llvm.buildAdd(self.builder, current_iter, llvm.constInt(i32_type, 1, 0), "iter.next\x00");
            _ = llvm.buildStore(self.builder, next_iter, iter_alloca);
            _ = llvm.buildBr(self.builder, cond_block);
        }

        if (prev_iterator_value) |prev_val| {
            try self.named_values.put(for_stmt.iterator, prev_val);
        } else {
            _ = self.named_values.remove(for_stmt.iterator);
        }

        if (prev_iterator_type) |prev_type| {
            try self.named_types.put(for_stmt.iterator, prev_type);
        } else {
            _ = self.named_types.remove(for_stmt.iterator);
        }

        llvm.positionBuilderAtEnd(self.builder, exit_block);
    }

    fn generateForArray(self: *LLVMBackend, for_stmt: ast.ForStmt, current_func: *llvm.ValueRef) !void {
        const iterable_type = try self.inferExpressionType(for_stmt.iterable);

        if (iterable_type != .array) {
            return error.TypeInferenceFailed;
        }

        const array_len = iterable_type.array.size;
        const elem_type = try self.type_mapper.mapType(iterable_type.array.element_type.*);

        const i32_type = llvm.int32Type(self.context);
        const counter_alloca = llvm.buildAlloca(self.builder, i32_type, "for.counter\x00");
        _ = llvm.buildStore(self.builder, llvm.constInt(i32_type, 0, 0), counter_alloca);

        const elem_alloca = llvm.buildAlloca(self.builder, elem_type, "for.elem\x00");

        const cond_block = llvm.appendBasicBlock(self.context, current_func, "for.cond\x00");
        const body_block = llvm.appendBasicBlock(self.context, current_func, "for.body\x00");
        const exit_block = llvm.appendBasicBlock(self.context, current_func, "for.exit\x00");

        _ = llvm.buildBr(self.builder, cond_block);

        llvm.positionBuilderAtEnd(self.builder, cond_block);
        const counter_val = llvm.buildLoad(self.builder, i32_type, counter_alloca, "counter\x00");
        const array_len_val = llvm.constInt(i32_type, @intCast(array_len), 0);
        const cond = llvm.buildICmp(self.builder, .slt, counter_val, array_len_val, "for.cond\x00");
        _ = llvm.buildCondBr(self.builder, cond, body_block, exit_block);

        llvm.positionBuilderAtEnd(self.builder, body_block);

        const iterable_ptr = if (for_stmt.iterable.* == .identifier)
            self.named_values.get(for_stmt.iterable.identifier.name) orelse return error.UndefinedVariable
        else
            try self.generateExpression(for_stmt.iterable);

        const array_type = llvm.arrayType(elem_type, @intCast(array_len));
        const indices = [_]*llvm.ValueRef{ llvm.constInt(i32_type, 0, 0), counter_val };
        const elem_ptr = llvm.buildGEP(self.builder, array_type, iterable_ptr, &indices, 2, "elem.ptr\x00");
        const elem_val = llvm.buildLoad(self.builder, elem_type, elem_ptr, "elem\x00");
        _ = llvm.buildStore(self.builder, elem_val, elem_alloca);

        const prev_iterator_value = self.named_values.get(for_stmt.iterator);
        const prev_iterator_type = self.named_types.get(for_stmt.iterator);
        try self.named_values.put(for_stmt.iterator, elem_alloca);
        try self.named_types.put(for_stmt.iterator, iterable_type.array.element_type.*);

        for (for_stmt.body) |stmt| {
            try self.generateStatement(stmt);
        }

        const next_counter = llvm.buildAdd(self.builder, counter_val, llvm.constInt(i32_type, 1, 0), "counter.next\x00");
        _ = llvm.buildStore(self.builder, next_counter, counter_alloca);
        _ = llvm.buildBr(self.builder, cond_block);

        if (prev_iterator_value) |prev_val| {
            try self.named_values.put(for_stmt.iterator, prev_val);
        } else {
            _ = self.named_values.remove(for_stmt.iterator);
        }

        if (prev_iterator_type) |prev_type| {
            try self.named_types.put(for_stmt.iterator, prev_type);
        } else {
            _ = self.named_types.remove(for_stmt.iterator);
        }

        llvm.positionBuilderAtEnd(self.builder, exit_block);
    }

    fn inferExpressionType(self: *LLVMBackend, expr: *ast.Expr) !types.ResolvedType {
        return switch (expr.*) {
            .number => types.ResolvedType.i32,
            .string => types.ResolvedType.string_type,
            .bool_literal => types.ResolvedType.bool_type,
            .identifier => |ident| {
                // first check local variables and parameters
                // types are arena-managed, return directly
                if (self.named_types.get(ident.name)) |local_type| {
                    return local_type;
                }

                // look up in symbol table for global variables
                const symbol = self.symbols.global_scope.symbols.get(ident.name) orelse return error.TypeInferenceFailed;
                return switch (symbol) {
                    // types are arena-managed, return directly
                    .variable => |v| v.type_annotation,
                    else => error.TypeInferenceFailed,
                };
            },
            .call => |call| {
                // callee must be an identifier for now
                if (call.callee.* != .identifier) return error.TypeInferenceFailed;
                const func_name = call.callee.identifier.name;

                const symbol = self.symbols.global_scope.symbols.get(func_name) orelse return error.TypeInferenceFailed;
                if (symbol != .function) return error.TypeInferenceFailed;

                // if function has error domain, it returns Result<T, E>
                // types are arena-managed, no clone needed
                if (symbol.function.error_domain != null) {
                    const ok_type_ptr = try self.allocator.create(types.ResolvedType);
                    ok_type_ptr.* = symbol.function.return_type;
                    return types.ResolvedType{
                        .result = .{
                            .ok_type = ok_type_ptr,
                            .error_domain = symbol.function.error_domain.?,
                        },
                    };
                }
                // types are arena-managed, return directly
                return symbol.function.return_type;
            },
            .binary => |bin_op| {
                // comparison and logical operations return Bool
                // primitive types don't need cloning
                return switch (bin_op.op) {
                    .eq, .ne, .lt, .gt, .le, .ge, .logical_and, .logical_or => types.ResolvedType.bool_type,
                    else => try self.inferExpressionType(bin_op.left),
                };
            },
            .unary => |un_op| {
                return try self.inferExpressionType(un_op.operand);
            },
            .array_literal => |al| {
                if (al.elements.len == 0) return error.TypeInferenceFailed;
                const elem_type = try self.inferExpressionType(al.elements[0]);
                const elem_type_ptr = try self.allocator.create(types.ResolvedType);
                elem_type_ptr.* = elem_type;
                return types.ResolvedType{
                    .array = .{
                        .element_type = elem_type_ptr,
                        .size = al.elements.len,
                    },
                };
            },
            .range => |r| {
                const elem_type = try self.inferExpressionType(r.start);
                const elem_type_ptr = try self.allocator.create(types.ResolvedType);
                elem_type_ptr.* = elem_type;
                return types.ResolvedType{ .range = .{ .element_type = elem_type_ptr } };
            },
            .ok => |ok_expr| {
                // ok wraps a value in Result, return the inner type for codegen purposes
                return try self.inferExpressionType(ok_expr);
            },
            .err => {
                // err produces a Result; return i32 as placeholder since error path has no value
                return types.ResolvedType.i32;
            },
            .check => |check_expr| {
                // check unwraps a Result<T, E> to T
                // need to look up the called function's return type
                if (check_expr.expr.* == .call) {
                    const call = check_expr.expr.call;
                    if (call.callee.* == .identifier) {
                        const func_name = call.callee.identifier.name;
                        const symbol = self.symbols.global_scope.symbols.get(func_name) orelse return error.TypeInferenceFailed;
                        if (symbol == .function) {
                            // types are arena-managed, return directly
                            return symbol.function.return_type;
                        }
                    }
                }
                return error.TypeInferenceFailed;
            },
            .ensure => {
                // ensure returns Unit on success
                return types.ResolvedType.unit_type;
            },
            .map_error => |map_error_expr| {
                // map_error transforms error domain but preserves ok type
                return try self.inferExpressionType(map_error_expr.expr);
            },
            .record_literal => |rl| {
                // build record type from fields
                const field_count = rl.fields.len;
                if (field_count == 0) return types.ResolvedType.unit_type;

                const field_names = try self.allocator.alloc([]const u8, field_count);
                var names_initialized: usize = 0;
                errdefer {
                    for (field_names[0..names_initialized]) |name| {
                        self.allocator.free(name);
                    }
                    self.allocator.free(field_names);
                }

                const field_types = try self.allocator.alloc(types.ResolvedType, field_count);
                // types are arena-managed, only free the array on error
                errdefer self.allocator.free(field_types);

                for (rl.fields, 0..) |field, i| {
                    // duplicate field name so it's owned by this type
                    field_names[i] = try self.allocator.dupe(u8, field.name);
                    names_initialized += 1;
                    field_types[i] = try self.inferExpressionType(field.value);
                }

                return types.ResolvedType{
                    .record = .{
                        .field_names = field_names,
                        .field_types = field_types,
                        .field_locations = null,
                    },
                };
            },
            .field_access => |fa| {
                // infer type based on object type and field name
                // types are arena-managed, no deinit needed
                const object_type = try self.inferExpressionType(fa.object);

                switch (object_type) {
                    .record => |rec| {
                        for (rec.field_names, 0..) |name, i| {
                            if (std.mem.eql(u8, name, fa.field)) {
                                // types are arena-managed, return directly
                                return rec.field_types[i];
                            }
                        }
                        return error.TypeInferenceFailed;
                    },
                    .result => |res| {
                        if (std.mem.eql(u8, fa.field, "tag")) {
                            return types.ResolvedType.i8;
                        } else if (std.mem.eql(u8, fa.field, "value")) {
                            // types are arena-managed, return directly
                            return res.ok_type.*;
                        } else if (std.mem.eql(u8, fa.field, "error_code")) {
                            return types.ResolvedType.i64;
                        }
                        return error.TypeInferenceFailed;
                    },
                    .nullable => |inner| {
                        if (std.mem.eql(u8, fa.field, "has_value")) {
                            return types.ResolvedType.bool_type;
                        } else if (std.mem.eql(u8, fa.field, "value")) {
                            // types are arena-managed, return directly
                            return inner.*;
                        }
                        return error.TypeInferenceFailed;
                    },
                    .string_type => {
                        if (std.mem.eql(u8, fa.field, "len")) {
                            return types.ResolvedType.i64;
                        } else if (std.mem.eql(u8, fa.field, "ptr")) {
                            return types.ResolvedType.usize_type;
                        }
                        return error.TypeInferenceFailed;
                    },
                    .array => |arr| {
                        if (std.mem.eql(u8, fa.field, "len")) {
                            return types.ResolvedType{ .const_value = .{ .value = arr.size, .const_type = try self.allocator.create(types.ResolvedType) } };
                        }
                        return error.TypeInferenceFailed;
                    },
                    else => return error.TypeInferenceFailed,
                }
            },
            .null_literal => {
                // null is nullable; return nullable i64 as default when context is unavailable
                const inner_ptr = try self.allocator.create(types.ResolvedType);
                inner_ptr.* = types.ResolvedType.i64;
                return types.ResolvedType{ .nullable = inner_ptr };
            },
            .match_expr => |me| {
                // try to infer type from arm bodies
                // some arms may have pattern bindings that aren't in named_types yet,
                // so try all arms and return the first one that succeeds
                for (me.arms) |arm| {
                    const arm_type = self.inferExpressionType(arm.body) catch continue;
                    return arm_type;
                }
                return types.ResolvedType.unit_type;
            },
            .variant_constructor => |vc| {
                // look up the actual union type containing this variant from symbol table
                var iter = self.symbols.global_scope.symbols.iterator();
                while (iter.next()) |entry| {
                    const symbol = entry.value_ptr.*;
                    if (symbol == .type_def) {
                        const type_def = symbol.type_def;
                        // check if this type is a union type with the matching variant
                        if (type_def.underlying == .union_type) {
                            for (type_def.underlying.union_type.variants) |variant| {
                                if (std.mem.eql(u8, variant.name, vc.variant_name)) {
                                    // found it - return a named type pointing to this union
                                    // types are arena-managed, no clone needed
                                    const underlying_ptr = try self.allocator.create(types.ResolvedType);
                                    underlying_ptr.* = type_def.underlying;
                                    return types.ResolvedType{
                                        .named = .{
                                            .name = type_def.name,
                                            .underlying = underlying_ptr,
                                        },
                                    };
                                }
                            }
                        }
                    }
                }
                // variant not found in any union type
                return error.TypeInferenceFailed;
            },
            .block_expr => |be| {
                return try self.inferBlockExprType(be);
            },
            else => error.TypeInferenceFailed,
        };
    }

    /// infers the type of a block expression by analyzing its statements and result
    fn inferBlockExprType(self: *LLVMBackend, block_expr: ast.BlockExpr) !types.ResolvedType {
        // temporarily track local variable types for this block
        // types are arena-managed, no deinit needed for values
        var local_types = std.StringHashMap(types.ResolvedType).init(self.allocator);
        defer local_types.deinit();

        // process each statement to build local type context
        for (block_expr.statements) |stmt| {
            switch (stmt) {
                .const_decl => |cd| {
                    // infer the type of the const value
                    const value_type = self.inferExprWithLocals(cd.value, &local_types) catch continue;
                    try local_types.put(cd.name, value_type);
                },
                .var_decl => |vd| {
                    // infer the type of the var value
                    const value_type = self.inferExprWithLocals(vd.value, &local_types) catch continue;
                    try local_types.put(vd.name, value_type);
                },
                else => {},
            }
        }

        // infer the result expression type using local context
        if (block_expr.result_expr) |result| {
            return try self.inferExprWithLocals(result, &local_types);
        }

        // no result expression means unit type
        return types.ResolvedType.unit_type;
    }

    /// infers expression type with additional local variable context
    fn inferExprWithLocals(self: *LLVMBackend, expr: *ast.Expr, local_types: *std.StringHashMap(types.ResolvedType)) error{ OutOfMemory, TypeInferenceFailed }!types.ResolvedType {
        return switch (expr.*) {
            .identifier => |ident| {
                // first check local block variables
                // types are arena-managed, return directly
                if (local_types.get(ident.name)) |local_type| {
                    return local_type;
                }
                // then check named_types (function-level locals and params)
                if (self.named_types.get(ident.name)) |named_type| {
                    return named_type;
                }
                // finally check global symbols
                const symbol = self.symbols.global_scope.symbols.get(ident.name) orelse return error.TypeInferenceFailed;
                return switch (symbol) {
                    .variable => |v| v.type_annotation,
                    else => error.TypeInferenceFailed,
                };
            },
            .binary => |bin_op| {
                return switch (bin_op.op) {
                    .eq, .ne, .lt, .gt, .le, .ge, .logical_and, .logical_or => types.ResolvedType.bool_type,
                    else => try self.inferExprWithLocals(bin_op.left, local_types),
                };
            },
            .number => types.ResolvedType.i32,
            .string => types.ResolvedType.string_type,
            .bool_literal => types.ResolvedType.bool_type,
            .block_expr => |be| {
                // recursively handle nested blocks
                // create a new local context that includes parent locals
                // types are arena-managed, no deinit needed for values
                var nested_locals = std.StringHashMap(types.ResolvedType).init(self.allocator);
                defer nested_locals.deinit();

                // copy parent locals (types are arena-managed, no clone needed)
                var parent_iter = local_types.iterator();
                while (parent_iter.next()) |entry| {
                    try nested_locals.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                // process nested block statements
                for (be.statements) |stmt| {
                    switch (stmt) {
                        .const_decl => |cd| {
                            const value_type = self.inferExprWithLocals(cd.value, &nested_locals) catch continue;
                            try nested_locals.put(cd.name, value_type);
                        },
                        .var_decl => |vd| {
                            const value_type = self.inferExprWithLocals(vd.value, &nested_locals) catch continue;
                            try nested_locals.put(vd.name, value_type);
                        },
                        else => {},
                    }
                }

                if (be.result_expr) |result| {
                    return try self.inferExprWithLocals(result, &nested_locals);
                }
                return types.ResolvedType.unit_type;
            },
            // for other expressions, fall back to regular inference
            else => try self.inferExpressionType(expr),
        };
    }

    pub fn emitToString(self: *LLVMBackend) ![]const u8 {
        const ir_str = llvm.moduleToString(self.module);
        defer llvm.disposeMessage(ir_str);

        return try self.allocator.dupe(u8, std.mem.span(ir_str));
    }

    pub fn writeIRToFile(self: *LLVMBackend, filename: []const u8) !void {
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        var error_msg: [*:0]u8 = undefined;
        const result = llvm.printModuleToFile(self.module, filename_z.ptr, &error_msg);
        if (result != 0) {
            defer llvm.disposeMessage(error_msg);
            const err_str = std.mem.span(error_msg);
            std.debug.print("failed to write IR to file: {s}\n", .{err_str});
            return error.LLVMWriteIRFailed;
        }
    }
};
