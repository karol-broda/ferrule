// minimal LLVM C API bindings for Ferrule codegen
// using Zig's C interop

pub const ContextRef = opaque {};
pub const ModuleRef = opaque {};
pub const TypeRef = opaque {};
pub const ValueRef = opaque {};
pub const BasicBlockRef = opaque {};
pub const BuilderRef = opaque {};

extern fn LLVMContextCreate() ?*ContextRef;
extern fn LLVMContextDispose(ctx: *ContextRef) void;
extern fn LLVMModuleCreateWithNameInContext(name: [*:0]const u8, ctx: *ContextRef) ?*ModuleRef;
extern fn LLVMDisposeModule(m: *ModuleRef) void;
extern fn LLVMPrintModuleToString(m: *ModuleRef) [*:0]u8;
extern fn LLVMDisposeMessage(msg: [*:0]u8) void;
extern fn LLVMCreateBuilderInContext(ctx: *ContextRef) ?*BuilderRef;
extern fn LLVMDisposeBuilder(builder: *BuilderRef) void;

// type creation
extern fn LLVMVoidTypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt1TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt8TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt16TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt32TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt64TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMInt128TypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMHalfTypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMFloatTypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMDoubleTypeInContext(ctx: *ContextRef) *TypeRef;
extern fn LLVMArrayType(elem: *TypeRef, count: c_uint) *TypeRef;
extern fn LLVMPointerType(elem: *TypeRef, addr_space: c_uint) *TypeRef;
extern fn LLVMStructTypeInContext(ctx: *ContextRef, elem_types: [*]const *TypeRef, elem_count: c_uint, is_packed: c_int) *TypeRef;
extern fn LLVMFunctionType(ret: *TypeRef, params: [*]const *TypeRef, param_count: c_uint, is_var_arg: c_int) *TypeRef;
extern fn LLVMVectorType(elem: *TypeRef, count: c_uint) *TypeRef;

// function/value creation
extern fn LLVMAddFunction(m: *ModuleRef, name: [*:0]const u8, func_type: *TypeRef) *ValueRef;
extern fn LLVMGetParam(fn_val: *ValueRef, index: c_uint) *ValueRef;
extern fn LLVMAppendBasicBlockInContext(ctx: *ContextRef, fn_val: *ValueRef, name: [*:0]const u8) *BasicBlockRef;
extern fn LLVMPositionBuilderAtEnd(builder: *BuilderRef, block: *BasicBlockRef) void;

// constants
extern fn LLVMConstInt(ty: *TypeRef, val: c_ulonglong, sign_extend: c_int) *ValueRef;
extern fn LLVMConstReal(ty: *TypeRef, val: f64) *ValueRef;
extern fn LLVMConstStringInContext(ctx: *ContextRef, str: [*]const u8, len: c_uint, dont_null_terminate: c_int) *ValueRef;
extern fn LLVMConstStructInContext(ctx: *ContextRef, vals: [*]const *ValueRef, count: c_uint, is_packed: c_int) *ValueRef;

// instructions
extern fn LLVMBuildRet(builder: *BuilderRef, val: *ValueRef) *ValueRef;
extern fn LLVMBuildRetVoid(builder: *BuilderRef) *ValueRef;
extern fn LLVMBuildAdd(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildSub(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildMul(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildSDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildUDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildFAdd(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildFSub(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildFMul(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildFDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildAlloca(builder: *BuilderRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildStore(builder: *BuilderRef, val: *ValueRef, ptr: *ValueRef) *ValueRef;
extern fn LLVMBuildLoad2(builder: *BuilderRef, ty: *TypeRef, ptr: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildCall2(builder: *BuilderRef, ty: *TypeRef, fn_val: *ValueRef, args: [*]const *ValueRef, num_args: c_uint, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildICmp(builder: *BuilderRef, op: IntPredicate, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildFCmp(builder: *BuilderRef, op: RealPredicate, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildBr(builder: *BuilderRef, dest: *BasicBlockRef) *ValueRef;
extern fn LLVMBuildCondBr(builder: *BuilderRef, cond: *ValueRef, then_block: *BasicBlockRef, else_block: *BasicBlockRef) *ValueRef;
extern fn LLVMBuildPhi(builder: *BuilderRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMAddIncoming(phi: *ValueRef, incoming_values: [*]const *ValueRef, incoming_blocks: [*]const *BasicBlockRef, count: c_uint) void;
extern fn LLVMBuildGEP2(builder: *BuilderRef, ty: *TypeRef, ptr: *ValueRef, indices: [*]const *ValueRef, num_indices: c_uint, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildExtractValue(builder: *BuilderRef, agg_val: *ValueRef, index: c_uint, name: [*:0]const u8) *ValueRef;
extern fn LLVMBuildInsertValue(builder: *BuilderRef, agg_val: *ValueRef, elem_val: *ValueRef, index: c_uint, name: [*:0]const u8) *ValueRef;

// globals
extern fn LLVMAddGlobal(m: *ModuleRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef;
extern fn LLVMSetInitializer(global: *ValueRef, constant_val: *ValueRef) void;
extern fn LLVMSetGlobalConstant(global: *ValueRef, is_constant: c_int) void;

pub const IntPredicate = enum(c_uint) {
    eq = 32,
    ne = 33,
    ugt = 34,
    uge = 35,
    ult = 36,
    ule = 37,
    sgt = 38,
    sge = 39,
    slt = 40,
    sle = 41,
};

pub const RealPredicate = enum(c_uint) {
    oeq = 1,
    one = 6,
    ogt = 2,
    oge = 3,
    olt = 4,
    ole = 5,
};

// wrapper functions for cleaner API
pub fn contextCreate() ?*ContextRef {
    return LLVMContextCreate();
}

pub fn contextDispose(ctx: *ContextRef) void {
    LLVMContextDispose(ctx);
}

pub fn moduleCreate(name: [*:0]const u8, ctx: *ContextRef) ?*ModuleRef {
    return LLVMModuleCreateWithNameInContext(name, ctx);
}

pub fn moduleDispose(m: *ModuleRef) void {
    LLVMDisposeModule(m);
}

pub fn moduleToString(m: *ModuleRef) [*:0]u8 {
    return LLVMPrintModuleToString(m);
}

pub fn disposeMessage(msg: [*:0]u8) void {
    LLVMDisposeMessage(msg);
}

pub fn builderCreate(ctx: *ContextRef) ?*BuilderRef {
    return LLVMCreateBuilderInContext(ctx);
}

pub fn builderDispose(builder: *BuilderRef) void {
    LLVMDisposeBuilder(builder);
}

extern fn LLVMGetBasicBlockTerminator(bb: *BasicBlockRef) ?*ValueRef;
pub fn getBasicBlockTerminator(bb: *BasicBlockRef) ?*ValueRef {
    return LLVMGetBasicBlockTerminator(bb);
}

extern fn LLVMDeleteBasicBlock(bb: *BasicBlockRef) void;
pub fn deleteBasicBlock(bb: *BasicBlockRef) void {
    LLVMDeleteBasicBlock(bb);
}

// type helpers
pub fn voidType(ctx: *ContextRef) *TypeRef {
    return LLVMVoidTypeInContext(ctx);
}

pub fn int1Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt1TypeInContext(ctx);
}

pub fn int8Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt8TypeInContext(ctx);
}

pub fn int16Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt16TypeInContext(ctx);
}

pub fn int32Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt32TypeInContext(ctx);
}

pub fn int64Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt64TypeInContext(ctx);
}

pub fn int128Type(ctx: *ContextRef) *TypeRef {
    return LLVMInt128TypeInContext(ctx);
}

pub fn halfType(ctx: *ContextRef) *TypeRef {
    return LLVMHalfTypeInContext(ctx);
}

pub fn floatType(ctx: *ContextRef) *TypeRef {
    return LLVMFloatTypeInContext(ctx);
}

pub fn doubleType(ctx: *ContextRef) *TypeRef {
    return LLVMDoubleTypeInContext(ctx);
}

pub fn arrayType(elem: *TypeRef, count: c_uint) *TypeRef {
    return LLVMArrayType(elem, count);
}

pub fn pointerType(elem: *TypeRef, addr_space: c_uint) *TypeRef {
    return LLVMPointerType(elem, addr_space);
}

pub fn structTypeInContext(ctx: *ContextRef, elem_types: [*]const *TypeRef, count: c_uint, is_packed: c_int) *TypeRef {
    return LLVMStructTypeInContext(ctx, elem_types, count, is_packed);
}

pub fn functionType(ret: *TypeRef, params: [*]const *TypeRef, param_count: c_uint, is_var_arg: c_int) *TypeRef {
    return LLVMFunctionType(ret, params, param_count, is_var_arg);
}

pub fn vectorType(elem: *TypeRef, count: c_uint) *TypeRef {
    return LLVMVectorType(elem, count);
}

// value/function helpers
pub fn addFunction(m: *ModuleRef, name: [*:0]const u8, func_type: *TypeRef) *ValueRef {
    return LLVMAddFunction(m, name, func_type);
}

pub fn getParam(fn_val: *ValueRef, index: c_uint) *ValueRef {
    return LLVMGetParam(fn_val, index);
}

pub fn appendBasicBlock(ctx: *ContextRef, fn_val: *ValueRef, name: [*:0]const u8) *BasicBlockRef {
    return LLVMAppendBasicBlockInContext(ctx, fn_val, name);
}

pub fn positionBuilderAtEnd(builder: *BuilderRef, block: *BasicBlockRef) void {
    LLVMPositionBuilderAtEnd(builder, block);
}

// constant helpers
pub fn constInt(ty: *TypeRef, val: c_ulonglong, sign_extend: c_int) *ValueRef {
    return LLVMConstInt(ty, val, sign_extend);
}

pub fn constReal(ty: *TypeRef, val: f64) *ValueRef {
    return LLVMConstReal(ty, val);
}

pub fn constString(ctx: *ContextRef, str: [*]const u8, len: c_uint, dont_null_terminate: c_int) *ValueRef {
    return LLVMConstStringInContext(ctx, str, len, dont_null_terminate);
}

extern fn LLVMConstPointerCast(const_val: *ValueRef, to_type: *TypeRef) *ValueRef;
pub fn constPointerCast(const_val: *ValueRef, to_type: *TypeRef) *ValueRef {
    return LLVMConstPointerCast(const_val, to_type);
}

pub fn constStruct(ctx: *ContextRef, vals: [*]const *ValueRef, count: c_uint, is_packed: c_int) *ValueRef {
    return LLVMConstStructInContext(ctx, vals, count, is_packed);
}

// instruction helpers
pub fn buildRet(builder: *BuilderRef, val: *ValueRef) *ValueRef {
    return LLVMBuildRet(builder, val);
}

pub fn buildRetVoid(builder: *BuilderRef) *ValueRef {
    return LLVMBuildRetVoid(builder);
}

pub fn buildAdd(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildAdd(builder, lhs, rhs, name);
}

pub fn buildSub(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildSub(builder, lhs, rhs, name);
}

pub fn buildMul(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildMul(builder, lhs, rhs, name);
}

pub fn buildSDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildSDiv(builder, lhs, rhs, name);
}

pub fn buildUDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildUDiv(builder, lhs, rhs, name);
}

pub fn buildFAdd(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildFAdd(builder, lhs, rhs, name);
}

pub fn buildFSub(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildFSub(builder, lhs, rhs, name);
}

pub fn buildFMul(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildFMul(builder, lhs, rhs, name);
}

pub fn buildFDiv(builder: *BuilderRef, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildFDiv(builder, lhs, rhs, name);
}

pub fn buildAlloca(builder: *BuilderRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildAlloca(builder, ty, name);
}

pub fn buildStore(builder: *BuilderRef, val: *ValueRef, ptr: *ValueRef) *ValueRef {
    return LLVMBuildStore(builder, val, ptr);
}

pub fn buildLoad(builder: *BuilderRef, ty: *TypeRef, ptr: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildLoad2(builder, ty, ptr, name);
}

pub fn buildCall(builder: *BuilderRef, ty: *TypeRef, fn_val: *ValueRef, args: [*]const *ValueRef, num_args: c_uint, name: [*:0]const u8) *ValueRef {
    return LLVMBuildCall2(builder, ty, fn_val, args, num_args, name);
}

pub fn buildICmp(builder: *BuilderRef, op: IntPredicate, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildICmp(builder, op, lhs, rhs, name);
}

pub fn buildFCmp(builder: *BuilderRef, op: RealPredicate, lhs: *ValueRef, rhs: *ValueRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildFCmp(builder, op, lhs, rhs, name);
}

pub fn buildBr(builder: *BuilderRef, dest: *BasicBlockRef) *ValueRef {
    return LLVMBuildBr(builder, dest);
}

pub fn buildCondBr(builder: *BuilderRef, cond: *ValueRef, then_block: *BasicBlockRef, else_block: *BasicBlockRef) *ValueRef {
    return LLVMBuildCondBr(builder, cond, then_block, else_block);
}

pub fn buildPhi(builder: *BuilderRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef {
    return LLVMBuildPhi(builder, ty, name);
}

pub fn addIncoming(phi: *ValueRef, incoming_values: [*]const *ValueRef, incoming_blocks: [*]const *BasicBlockRef, count: c_uint) void {
    LLVMAddIncoming(phi, incoming_values, incoming_blocks, count);
}

pub fn buildGEP(builder: *BuilderRef, ty: *TypeRef, ptr: *ValueRef, indices: [*]const *ValueRef, num_indices: c_uint, name: [*:0]const u8) *ValueRef {
    return LLVMBuildGEP2(builder, ty, ptr, indices, num_indices, name);
}

pub fn buildExtractValue(builder: *BuilderRef, agg_val: *ValueRef, index: c_uint, name: [*:0]const u8) *ValueRef {
    return LLVMBuildExtractValue(builder, agg_val, index, name);
}

pub fn buildInsertValue(builder: *BuilderRef, agg_val: *ValueRef, elem_val: *ValueRef, index: c_uint, name: [*:0]const u8) *ValueRef {
    return LLVMBuildInsertValue(builder, agg_val, elem_val, index, name);
}

pub fn addGlobal(m: *ModuleRef, ty: *TypeRef, name: [*:0]const u8) *ValueRef {
    return LLVMAddGlobal(m, ty, name);
}

pub fn setInitializer(global: *ValueRef, constant_val: *ValueRef) void {
    LLVMSetInitializer(global, constant_val);
}

pub fn setGlobalConstant(global: *ValueRef, is_constant: c_int) void {
    LLVMSetGlobalConstant(global, is_constant);
}
