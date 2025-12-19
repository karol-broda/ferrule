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
        fields: ?[]Pattern,
    },
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
};

pub const IndexAccessExpr = struct {
    object: *Expr,
    index: *Expr,
};

pub const RecordLiteralExpr = struct {
    fields: []FieldAssignment,
};

pub const FieldAssignment = struct {
    name: []const u8,
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

    pub fn deinit(self: *const ImportDecl, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
    }
};

pub const Module = struct {
    package_decl: ?PackageDecl,
    imports: []ImportDecl,
    statements: []Stmt,

    pub fn deinit(self: *const Module, allocator: std.mem.Allocator) void {
        if (self.package_decl) |pd| {
            allocator.free(pd.name);
        }

        for (self.imports) |import_decl| {
            allocator.free(import_decl.items);
        }
        allocator.free(self.imports);

        for (self.statements) |stmt| {
            deinitStmt(&stmt, allocator);
        }
        allocator.free(self.statements);
    }
};

pub fn deinitStmt(stmt: *const Stmt, allocator: std.mem.Allocator) void {
    switch (stmt.*) {
        .const_decl => |cd| {
            if (cd.type_annotation) |ta| {
                deinitType(&ta, allocator);
            }
            deinitExpr(cd.value, allocator);
        },
        .var_decl => |vd| {
            if (vd.type_annotation) |ta| {
                deinitType(&ta, allocator);
            }
            deinitExpr(vd.value, allocator);
        },
        .function_decl => |fd| {
            if (fd.type_params) |tps| {
                for (tps) |tp| {
                    if (tp.constraint) |c| {
                        deinitType(&c, allocator);
                    }
                    if (tp.const_type) |ct| {
                        deinitType(&ct, allocator);
                    }
                }
                allocator.free(tps);
            }
            for (fd.params) |param| {
                deinitType(&param.type_annotation, allocator);
            }
            allocator.free(fd.params);
            deinitType(&fd.return_type, allocator);
            allocator.free(fd.effects);
            for (fd.body) |body_stmt| {
                deinitStmt(&body_stmt, allocator);
            }
            allocator.free(fd.body);
        },
        .type_decl => |td| {
            deinitType(&td.type_expr, allocator);
        },
        .error_decl => |ed| {
            for (ed.fields) |field| {
                deinitType(&field.type_annotation, allocator);
            }
            allocator.free(ed.fields);
        },
        .domain_decl => |dd| {
            if (dd.error_union) |eu| {
                allocator.free(eu);
            }
            if (dd.variants) |variants| {
                for (variants) |variant| {
                    for (variant.fields) |field| {
                        deinitType(&field.type_annotation, allocator);
                    }
                    allocator.free(variant.fields);
                }
                allocator.free(variants);
            }
        },
        .return_stmt => |return_stmt| {
            if (return_stmt.value) |expr| {
                deinitExpr(expr, allocator);
            }
        },
        .defer_stmt => |expr| {
            deinitExpr(expr, allocator);
        },
        .expr_stmt => |expr| {
            deinitExpr(expr, allocator);
        },
        .assign_stmt => |as| {
            deinitExpr(as.value, allocator);
        },
        .if_stmt => |is| {
            deinitExpr(is.condition, allocator);
            for (is.then_block) |then_stmt| {
                deinitStmt(&then_stmt, allocator);
            }
            allocator.free(is.then_block);
            if (is.else_block) |eb| {
                for (eb) |else_stmt| {
                    deinitStmt(&else_stmt, allocator);
                }
                allocator.free(eb);
            }
        },
        .while_stmt => |ws| {
            deinitExpr(ws.condition, allocator);
            for (ws.body) |body_stmt| {
                deinitStmt(&body_stmt, allocator);
            }
            allocator.free(ws.body);
        },
        .for_stmt => |fs| {
            deinitExpr(fs.iterable, allocator);
            for (fs.body) |body_stmt| {
                deinitStmt(&body_stmt, allocator);
            }
            allocator.free(fs.body);
        },
        .match_stmt => |ms| {
            deinitExpr(ms.value, allocator);
            for (ms.arms) |arm| {
                deinitPattern(&arm.pattern, allocator);
                deinitExpr(arm.body, allocator);
            }
            allocator.free(ms.arms);
        },
        .break_stmt, .continue_stmt, .use_error => {},
        .package_decl, .import_decl => {},
    }
}

pub fn deinitExpr(expr: *const Expr, allocator: std.mem.Allocator) void {
    switch (expr.*) {
        .binary => |be| {
            deinitExpr(be.left, allocator);
            deinitExpr(be.right, allocator);
        },
        .unary => |ue| {
            deinitExpr(ue.operand, allocator);
        },
        .call => |ce| {
            deinitExpr(ce.callee, allocator);
            for (ce.args) |arg| {
                deinitExpr(arg, allocator);
            }
            allocator.free(ce.args);
        },
        .field_access => |fa| {
            deinitExpr(fa.object, allocator);
        },
        .index_access => |ia| {
            deinitExpr(ia.object, allocator);
            deinitExpr(ia.index, allocator);
        },
        .ok => |ok_expr| {
            deinitExpr(ok_expr, allocator);
        },
        .err => |ee| {
            for (ee.fields) |field| {
                deinitExpr(field.value, allocator);
            }
            allocator.free(ee.fields);
        },
        .check => |ce| {
            deinitExpr(ce.expr, allocator);
            if (ce.context_frame) |cf| {
                for (cf) |field| {
                    deinitExpr(field.value, allocator);
                }
                allocator.free(cf);
            }
        },
        .ensure => |ee| {
            deinitExpr(ee.condition, allocator);
            for (ee.error_expr.fields) |field| {
                deinitExpr(field.value, allocator);
            }
            allocator.free(ee.error_expr.fields);
        },
        .map_error => |me| {
            deinitExpr(me.expr, allocator);
            deinitExpr(me.transform, allocator);
        },
        .match_expr => |me| {
            deinitExpr(me.value, allocator);
            for (me.arms) |arm| {
                deinitPattern(&arm.pattern, allocator);
                deinitExpr(arm.body, allocator);
            }
            allocator.free(me.arms);
        },
        .array_literal => |al| {
            for (al.elements) |elem| {
                deinitExpr(elem, allocator);
            }
            allocator.free(al.elements);
        },
        .record_literal => |rl| {
            for (rl.fields) |field| {
                deinitExpr(field.value, allocator);
            }
            allocator.free(rl.fields);
        },
        .anonymous_function => |af| {
            for (af.params) |param| {
                deinitType(&param.type_annotation, allocator);
            }
            allocator.free(af.params);
            deinitType(&af.return_type, allocator);
            allocator.free(af.effects);
            for (af.body) |body_stmt| {
                deinitStmt(&body_stmt, allocator);
            }
            allocator.free(af.body);
        },
        .unsafe_cast => |uc| {
            deinitType(&uc.target_type, allocator);
            deinitExpr(uc.expr, allocator);
        },
        .comptime_expr => |ce| {
            deinitExpr(ce, allocator);
        },
        .context_block => |cb| {
            for (cb.context_items) |item| {
                deinitExpr(item.value, allocator);
            }
            allocator.free(cb.context_items);
            for (cb.body) |body_stmt| {
                deinitStmt(&body_stmt, allocator);
            }
            allocator.free(cb.body);
        },
        .range => |r| {
            deinitExpr(r.start, allocator);
            deinitExpr(r.end, allocator);
        },
        .number, .string, .bytes, .char, .identifier, .bool_literal, .null_literal, .unit_literal => {},
    }
    allocator.destroy(expr);
}

pub fn deinitType(type_expr: *const Type, allocator: std.mem.Allocator) void {
    switch (type_expr.*) {
        .simple => {},
        .generic => |gen| {
            for (gen.type_args) |*arg| {
                deinitType(arg, allocator);
            }
            allocator.free(gen.type_args);
        },
        .array => |arr| {
            deinitType(arr.element_type, allocator);
            allocator.destroy(arr.element_type);
            deinitExpr(arr.size, allocator);
        },
        .vector => |vec| {
            deinitType(vec.element_type, allocator);
            allocator.destroy(vec.element_type);
            deinitExpr(vec.size, allocator);
        },
        .view => |view| {
            deinitType(view.element_type, allocator);
            allocator.destroy(view.element_type);
        },
        .nullable => |nullable| {
            deinitType(nullable.inner, allocator);
            allocator.destroy(nullable.inner);
        },
        .function_type => |ft| {
            for (ft.params) |*param| {
                deinitType(param, allocator);
            }
            allocator.free(ft.params);
            deinitType(ft.return_type, allocator);
            allocator.destroy(ft.return_type);
            allocator.free(ft.effects);
        },
        .record_type => |rt| {
            for (rt.fields) |field| {
                deinitType(&field.type_annotation, allocator);
            }
            allocator.free(rt.fields);
        },
        .union_type => |ut| {
            for (ut.variants) |variant| {
                if (variant.fields) |fields| {
                    for (fields) |field| {
                        deinitType(&field.type_annotation, allocator);
                    }
                    allocator.free(fields);
                }
            }
            allocator.free(ut.variants);
        },
    }
}

fn deinitPattern(pattern: *const Pattern, allocator: std.mem.Allocator) void {
    switch (pattern.*) {
        .variant => |v| {
            if (v.fields) |fields| {
                for (fields) |field| {
                    deinitPattern(&field, allocator);
                }
                allocator.free(fields);
            }
        },
        .wildcard, .identifier, .number, .string => {},
    }
}
