const std = @import("std");

pub const Location = struct {
    line: usize,
    column: usize,
};

pub const Type = union(enum) {
    simple: struct {
        name: []const u8,
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
    domain_decl: DomainDecl,
    role_decl: RoleDecl,
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
    target: []const u8,
    value: *Expr,
};

pub const ConstDecl = struct {
    name: []const u8,
    type_annotation: ?Type,
    value: *Expr,
};

pub const VarDecl = struct {
    name: []const u8,
    type_annotation: ?Type,
    value: *Expr,
};

pub const Param = struct {
    name: []const u8,
    type_annotation: Type,
    is_inout: bool,
    is_capability: bool,
};

pub const FunctionDecl = struct {
    name: []const u8,
    params: []Param,
    return_type: Type,
    error_domain: ?[]const u8,
    effects: [][]const u8,
    body: []Stmt,
};

pub const TypeDecl = struct {
    name: []const u8,
    type_expr: Type,
};

pub const DomainVariant = struct {
    name: []const u8,
    fields: []Field,
};

pub const DomainDecl = struct {
    name: []const u8,
    variants: []DomainVariant,
};

pub const RoleDecl = struct {
    name: []const u8,
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

pub const Expr = union(enum) {
    number: []const u8,
    string: []const u8,
    char: []const u8,
    identifier: []const u8,
    bool_literal: bool,
    null_literal: void,
    binary: BinaryExpr,
    unary: UnaryExpr,
    call: CallExpr,
    field_access: FieldAccessExpr,
    ok: *Expr,
    err: ErrorExpr,
    check: CheckExpr,
    ensure: EnsureExpr,
    match_expr: MatchExpr,
};

pub const BinaryOp = enum {
    add,
    subtract,
    multiply,
    divide,
    modulo,
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

pub const ErrorExpr = struct {
    variant: []const u8,
    fields: []Field,
};

pub const CheckExpr = struct {
    expr: *Expr,
    context_frame: ?[]Field,
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

fn deinitStmt(stmt: *const Stmt, allocator: std.mem.Allocator) void {
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
        .domain_decl => |dd| {
            for (dd.variants) |variant| {
                for (variant.fields) |field| {
                    deinitType(&field.type_annotation, allocator);
                }
                allocator.free(variant.fields);
            }
            allocator.free(dd.variants);
        },
        .role_decl => {},
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

fn deinitExpr(expr: *const Expr, allocator: std.mem.Allocator) void {
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
        .ok => |ok_expr| {
            deinitExpr(ok_expr, allocator);
        },
        .err => |ee| {
            for (ee.fields) |field| {
                deinitType(&field.type_annotation, allocator);
            }
            allocator.free(ee.fields);
        },
        .check => |ce| {
            deinitExpr(ce.expr, allocator);
            if (ce.context_frame) |cf| {
                for (cf) |field| {
                    deinitType(&field.type_annotation, allocator);
                }
                allocator.free(cf);
            }
        },
        .ensure => |ee| {
            deinitExpr(ee.condition, allocator);
            for (ee.error_expr.fields) |field| {
                deinitType(&field.type_annotation, allocator);
            }
            allocator.free(ee.error_expr.fields);
        },
        .match_expr => |me| {
            deinitExpr(me.value, allocator);
            for (me.arms) |arm| {
                deinitPattern(&arm.pattern, allocator);
                deinitExpr(arm.body, allocator);
            }
            allocator.free(me.arms);
        },
        .number, .string, .char, .identifier, .bool_literal, .null_literal => {},
    }
    allocator.destroy(expr);
}

fn deinitType(type_expr: *const Type, allocator: std.mem.Allocator) void {
    switch (type_expr.*) {
        .simple => {},
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
            for (ft.params) |param| {
                deinitType(&param, allocator);
            }
            allocator.free(ft.params);
            deinitType(ft.return_type, allocator);
            allocator.destroy(ft.return_type);
            allocator.free(ft.effects);
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
