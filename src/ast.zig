const std = @import("std");

pub const Location = struct {
    line: usize,
    column: usize,
    length: usize = 0,
};

pub const Type = union(enum) {
    simple: struct {
        name: []const u8,
        loc: Location,
    },
    generic: struct {
        name: []const u8,
        type_args: []Type,
        loc: Location,
    },
    array: struct {
        element_type: *Type,
        size: *Expr,
        loc: Location,
    },
    vector: struct {
        element_type: *Type,
        size: *Expr,
        loc: Location,
    },
    view: struct {
        mutable: bool,
        element_type: *Type,
        loc: Location,
    },
    nullable: struct {
        inner: *Type,
        loc: Location,
    },
    function_type: struct {
        params: []Type,
        return_type: *Type,
        error_domain: ?[]const u8,
        effects: [][]const u8,
        loc: Location,
    },
    record_type: struct {
        fields: []RecordTypeField,
        loc: Location,
    },
    union_type: struct {
        variants: []UnionVariant,
        loc: Location,
    },
};

pub const RecordTypeField = struct {
    name: []const u8,
    type_annotation: Type,
};

pub const UnionVariant = struct {
    name: []const u8,
    fields: ?[]RecordTypeField,
};

pub const ReturnStmt = struct {
    value: ?*Expr,
    loc: Location,
};

pub const Stmt = union(enum) {
    const_decl: ConstDecl,
    var_decl: VarDecl,
    function_decl: FunctionDecl,
    type_decl: TypeDecl,
    error_decl: ErrorDecl,
    domain_decl: DomainDecl,
    return_stmt: ReturnStmt,
    defer_stmt: *Expr,
    expr_stmt: *Expr,
    assign_stmt: AssignStmt,
    if_stmt: IfStmt,
    while_stmt: WhileStmt,
    for_stmt: ForStmt,
    match_stmt: MatchStmt,
    break_stmt: void,
    continue_stmt: void,
    use_error: []const u8,
    package_decl: PackageDecl,
    import_decl: ImportDecl,
};

pub const AssignStmt = struct {
    target: IdentifierExpr,
    value: *Expr,
};

pub const ConstDecl = struct {
    name: []const u8,
    type_annotation: ?Type,
    value: *Expr,
    name_loc: Location,
};

pub const VarDecl = struct {
    name: []const u8,
    type_annotation: ?Type,
    value: *Expr,
    name_loc: Location,
};

pub const Param = struct {
    name: []const u8,
    type_annotation: Type,
    is_inout: bool,
    is_capability: bool,
    name_loc: Location,
};

pub const FunctionDecl = struct {
    name: []const u8,
    type_params: ?[]TypeParam,
    params: []Param,
    return_type: Type,
    error_domain: ?[]const u8,
    effects: [][]const u8,
    body: []Stmt,
    name_loc: Location,
};

pub const TypeDecl = struct {
    name: []const u8,
    type_params: ?[]TypeParam,
    type_expr: Type,
    name_loc: Location,
};

pub const TypeParam = struct {
    name: []const u8,
    variance: Variance,
    constraint: ?Type,
    is_const: bool,
    const_type: ?Type,
};

pub const Variance = enum {
    invariant,
    covariant, // out
    contravariant, // in
};

pub const ErrorDecl = struct {
    name: []const u8,
    fields: []Field,
    name_loc: Location,
};

pub const DomainVariant = struct {
    name: []const u8,
    fields: []Field,
};

pub const DomainDecl = struct {
    name: []const u8,
    // Either a union of error type names OR inline variants
    error_union: ?[][]const u8, // For: domain IoError = NotFound | Denied;
    variants: ?[]DomainVariant, // For: domain IoError { NotFound { path: String } }
    name_loc: Location,
};

pub const Field = struct {
    name: []const u8,
    type_annotation: Type,
};

pub const IfStmt = struct {
    condition: *Expr,
    then_block: []Stmt,
    else_block: ?[]Stmt,
};

pub const WhileStmt = struct {
    condition: *Expr,
    body: []Stmt,
};

pub const ForStmt = struct {
    iterator: []const u8,
    iterator_loc: Location,
    iterable: *Expr,
    body: []Stmt,
};

pub const MatchArm = struct {
    pattern: Pattern,
    body: *Expr,
};

pub const MatchStmt = struct {
    value: *Expr,
    arms: []MatchArm,
};

pub const Pattern = union(enum) {
    wildcard: void,
    identifier: []const u8,
    number: []const u8,
    string: []const u8,
    variant: struct {
        name: []const u8,
        fields: ?[]PatternField,
    },
    // result type patterns
    ok_pattern: struct {
        binding: ?[]const u8,
    },
    err_pattern: struct {
        variant_name: ?[]const u8,
        fields: ?[]PatternField,
    },
    // maybe type patterns
    some_pattern: struct {
        binding: ?[]const u8,
    },
    none_pattern: void,
};

pub const PatternField = struct {
    name: []const u8,
    pattern: ?*Pattern,
};

pub const IdentifierExpr = struct {
    name: []const u8,
    loc: Location,
};

pub const Expr = union(enum) {
    number: []const u8,
    string: []const u8,
    bytes: []const u8,
    char: []const u8,
    identifier: IdentifierExpr,
    bool_literal: bool,
    null_literal: void,
    unit_literal: void,
    binary: BinaryExpr,
    unary: UnaryExpr,
    call: CallExpr,
    field_access: FieldAccessExpr,
    index_access: IndexAccessExpr,
    array_literal: ArrayLiteralExpr,
    record_literal: RecordLiteralExpr,
    variant_constructor: VariantConstructorExpr,
    range: RangeExpr,
    ok: *Expr,
    err: ErrorExpr,
    check: CheckExpr,
    ensure: EnsureExpr,
    map_error: MapErrorExpr,
    match_expr: MatchExpr,
    anonymous_function: AnonymousFunctionExpr,
    unsafe_cast: UnsafeCastExpr,
    comptime_expr: *Expr,
    context_block: ContextBlockExpr,
    block_expr: BlockExpr,

    // returns location if available from the expression, including length when possible
    pub fn getLocation(self: *const Expr) ?Location {
        return switch (self.*) {
            .identifier => |id| .{
                .line = id.loc.line,
                .column = id.loc.column,
                .length = id.name.len,
            },
            .binary => |bin| bin.left.getLocation(),
            .unary => |un| un.operand.getLocation(),
            .call => |c| c.callee.getLocation(),
            .field_access => |fa| fa.object.getLocation(),
            .index_access => |ia| ia.object.getLocation(),
            .range => |r| r.start.getLocation(),
            .ok => |inner| inner.getLocation(),
            .check => |ch| ch.expr.getLocation(),
            .ensure => |en| en.condition.getLocation(),
            .map_error => |me| me.expr.getLocation(),
            .match_expr => |m| m.value.getLocation(),
            .unsafe_cast => |uc| uc.expr.getLocation(),
            .comptime_expr => |ce| ce.getLocation(),
            .variant_constructor => |vc| .{
                .line = vc.name_loc.line,
                .column = vc.name_loc.column,
                .length = vc.variant_name.len,
            },
            else => null,
        };
    }
};

pub const RangeExpr = struct {
    start: *Expr,
    end: *Expr,
    inclusive: bool,
};

pub const ArrayLiteralExpr = struct {
    elements: []*Expr,
};

pub const BinaryOp = enum {
    add,
    subtract,
    multiply,
    divide,
    modulo,
    concat, // ++
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    logical_and,
    logical_or,
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    shift_left,
    shift_right,
};

pub const BinaryExpr = struct {
    left: *Expr,
    op: BinaryOp,
    right: *Expr,
};

pub const UnaryOp = enum {
    negate,
    not,
    bitwise_not,
};

pub const UnaryExpr = struct {
    op: UnaryOp,
    operand: *Expr,
};

pub const CallExpr = struct {
    callee: *Expr,
    args: []*Expr,
};

pub const FieldAccessExpr = struct {
    object: *Expr,
    field: []const u8,
    field_loc: Location,
};

pub const IndexAccessExpr = struct {
    object: *Expr,
    index: *Expr,
};

pub const RecordLiteralExpr = struct {
    fields: []FieldAssignment,
};

pub const VariantConstructorExpr = struct {
    variant_name: []const u8,
    fields: ?[]FieldAssignment,
    name_loc: Location,
};

pub const FieldAssignment = struct {
    name: []const u8,
    name_loc: Location,
    value: *Expr,
};

pub const ErrorExpr = struct {
    variant: []const u8,
    fields: []FieldAssignment,
};

pub const MapErrorExpr = struct {
    expr: *Expr,
    param_name: []const u8,
    transform: *Expr,
};

pub const AnonymousFunctionExpr = struct {
    params: []Param,
    return_type: Type,
    error_domain: ?[]const u8,
    effects: [][]const u8,
    body: []Stmt,
};

pub const UnsafeCastExpr = struct {
    target_type: Type,
    expr: *Expr,
};

pub const ContextBlockExpr = struct {
    context_items: []FieldAssignment,
    body: []Stmt,
};

// block expression: { stmt1; stmt2; ...; result_expr }
// the last expression in the block is the result value
pub const BlockExpr = struct {
    statements: []Stmt,
    result_expr: ?*Expr, // final expression that produces the block's value
};

pub const CheckExpr = struct {
    expr: *Expr,
    context_frame: ?[]FieldAssignment,
};

pub const EnsureExpr = struct {
    condition: *Expr,
    error_expr: ErrorExpr,
};

pub const MatchExpr = struct {
    value: *Expr,
    arms: []MatchArm,
};

pub const PackageDecl = struct {
    name: []const u8,
};

pub const ImportItem = struct {
    name: []const u8,
    alias: ?[]const u8,
};

pub const ImportDecl = struct {
    source: []const u8,
    items: []ImportItem,
    capability: ?[]const u8,

    // no-op: memory is arena-managed
    pub fn deinit(self: *const ImportDecl, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const Module = struct {
    package_decl: ?PackageDecl,
    imports: []ImportDecl,
    statements: []Stmt,

    // no-op: memory is arena-managed
    pub fn deinit(self: *const Module, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

// no-op: memory is arena-managed
pub fn deinitStmt(stmt: *const Stmt, allocator: std.mem.Allocator) void {
    _ = stmt;
    _ = allocator;
}

// no-op: memory is arena-managed
pub fn deinitExpr(expr: *Expr, allocator: std.mem.Allocator) void {
    _ = expr;
    _ = allocator;
}

// no-op: memory is arena-managed
pub fn deinitType(type_expr: *const Type, allocator: std.mem.Allocator) void {
    _ = type_expr;
    _ = allocator;
}

// no-op: memory is arena-managed
fn deinitPatternField(field: *const PatternField, allocator: std.mem.Allocator) void {
    _ = field;
    _ = allocator;
}

// no-op: memory is arena-managed
pub fn deinitPattern(pattern: *const Pattern, allocator: std.mem.Allocator) void {
    _ = pattern;
    _ = allocator;
}
