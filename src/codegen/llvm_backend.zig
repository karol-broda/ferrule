const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const symbol_table = @import("../symbol_table.zig");
const llvm = @import("llvm_bindings.zig");
const TypeMapper = @import("llvm_types.zig").TypeMapper;

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

    // current function context
    current_function: ?*llvm.ValueRef,
    current_function_type: ?types.ResolvedType,
    current_function_decl: ?ast.FunctionDecl,

    pub fn init(allocator: std.mem.Allocator, module_name: []const u8, symbols: *symbol_table.SymbolTable, diagnostics_list: *@import("../diagnostics.zig").DiagnosticList, source_file: []const u8) !LLVMBackend {
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
            .current_function = null,
            .current_function_type = null,
            .current_function_decl = null,
        };
    }

    pub fn deinit(self: *LLVMBackend) void {
        self.named_values.deinit();

        var type_iter = self.named_types.valueIterator();
        while (type_iter.next()) |resolved_type| {
            resolved_type.deinit(self.allocator);
        }
        self.named_types.deinit();

        self.functions.deinit();
        llvm.builderDispose(self.builder);
        llvm.moduleDispose(self.module);
        llvm.contextDispose(self.context);
    }

    pub fn generateModule(self: *LLVMBackend, module: ast.Module) !void {
        // first pass: declare all functions
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.declareFunctionPrototype(stmt.function_decl);
            }
        }

        // second pass: generate function bodies
        for (module.statements) |stmt| {
            if (stmt == .function_decl) {
                try self.generateFunction(stmt.function_decl);
            }
        }
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

        // map return type
        const return_type = try self.type_mapper.mapType(func_info.return_type);

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

    fn generateFunction(self: *LLVMBackend, func_decl: ast.FunctionDecl) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock, FunctionNotDeclared, SymbolNotFound, NotAFunction }!void {
        const func = self.functions.get(func_decl.name) orelse return error.FunctionNotDeclared;

        const symbol = self.symbols.global_scope.symbols.get(func_decl.name) orelse return error.SymbolNotFound;
        if (symbol != .function) return error.NotAFunction;

        self.current_function = func;
        self.current_function_decl = func_decl;
        self.current_function_type = types.ResolvedType{ .function_type = .{
            .params = symbol.function.params,
            .return_type = try self.allocator.create(types.ResolvedType),
            .effects = symbol.function.effects,
            .error_domain = symbol.function.error_domain,
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

        // clear named values for new function scope
        self.named_values.clearRetainingCapacity();

        var type_iter = self.named_types.valueIterator();
        while (type_iter.next()) |resolved_type| {
            resolved_type.deinit(self.allocator);
        }
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

    fn generateStatement(self: *LLVMBackend, stmt: ast.Stmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock }!void {
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

            .role_decl => {
                // role declarations are for capability system, skip for now
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

    fn generateExpression(self: *LLVMBackend, expr: *ast.Expr) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber }!*llvm.ValueRef {
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
                const lhs = try self.generateExpression(bin_op.left);
                const rhs = try self.generateExpression(bin_op.right);

                const result_name = "binop\x00";
                const cmp_name = "cmp\x00";

                return switch (bin_op.op) {
                    .add => llvm.buildAdd(self.builder, lhs, rhs, result_name),
                    .subtract => llvm.buildSub(self.builder, lhs, rhs, result_name),
                    .multiply => llvm.buildMul(self.builder, lhs, rhs, result_name),
                    .divide => llvm.buildSDiv(self.builder, lhs, rhs, result_name),
                    .modulo => llvm.buildSDiv(self.builder, lhs, rhs, result_name), // TODO: use srem
                    .eq => llvm.buildICmp(self.builder, .eq, lhs, rhs, cmp_name),
                    .ne => llvm.buildICmp(self.builder, .ne, lhs, rhs, cmp_name),
                    .lt => llvm.buildICmp(self.builder, .slt, lhs, rhs, cmp_name),
                    .gt => llvm.buildICmp(self.builder, .sgt, lhs, rhs, cmp_name),
                    .le => llvm.buildICmp(self.builder, .sle, lhs, rhs, cmp_name),
                    .ge => llvm.buildICmp(self.builder, .sge, lhs, rhs, cmp_name),
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

                const ret_type = try self.type_mapper.mapType(symbol.function.return_type);
                const func_type = llvm.functionType(ret_type, param_types.ptr, @intCast(param_types.len), 0);

                const call_name = "call\x00";
                return llvm.buildCall(self.builder, func_type, func, args.ptr, @intCast(args.len), call_name);
            },

            else => return error.ExpressionNotImplemented,
        }
    }

    fn generateIfStatement(self: *LLVMBackend, if_stmt: ast.IfStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock }!void {
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
        const then_has_terminator = llvm.getBasicBlockTerminator(then_block) != null;
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
            else_has_terminator = llvm.getBasicBlockTerminator(else_bb) != null;
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

    fn generateWhileStatement(self: *LLVMBackend, while_stmt: ast.WhileStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock }!void {
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
        _ = llvm.buildBr(self.builder, cond_block);

        // exit block
        llvm.positionBuilderAtEnd(self.builder, exit_block);
    }

    fn generateForStatement(self: *LLVMBackend, for_stmt: ast.ForStmt) error{ OutOfMemory, UndefinedVariable, ExpressionNotImplemented, TypeInferenceFailed, FunctionNotFound, OperationNotImplemented, InvalidNumber, StatementNotImplemented, NoCurrentFunction, NoElseBlock }!void {
        const current_func = self.current_function orelse return error.NoCurrentFunction;

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
                if (self.named_types.get(ident.name)) |local_type| {
                    return local_type;
                }

                // look up in symbol table for global variables
                const symbol = self.symbols.global_scope.symbols.get(ident.name) orelse return error.TypeInferenceFailed;
                return switch (symbol) {
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
                return symbol.function.return_type;
            },
            .binary => |bin_op| {
                // for simplicity, assume both operands have same type
                return try self.inferExpressionType(bin_op.left);
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
            else => error.TypeInferenceFailed,
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
