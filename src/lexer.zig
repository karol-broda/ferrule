const std = @import("std");

pub const TokenType = enum {
    // keywords
    const_kw,
    var_kw,
    function_kw,
    return_kw,
    defer_kw,
    inout_kw,
    import_kw,
    export_kw,
    package_kw,
    type_kw,
    role_kw,
    domain_kw,
    effects_kw,
    capability_kw,
    with_kw,
    context_kw,
    match_kw,
    if_kw,
    else_kw,
    for_kw,
    while_kw,
    break_kw,
    continue_kw,
    comptime_kw,
    derivation_kw,
    use_kw,
    error_kw,
    as_kw,
    where_kw,
    asm_kw,
    component_kw,
    in_kw,
    using_kw,
    ok_kw,
    err_kw,
    check_kw,
    ensure_kw,
    map_error_kw,
    cap_kw,

    // literals
    identifier,
    number,
    string,
    char,
    true_kw,
    false_kw,
    null_kw,

    // operators
    plus,
    minus,
    star,
    slash,
    percent,
    ampersand,
    pipe,
    caret,
    tilde,
    bang,
    eq,
    eq_eq_eq, // ===
    bang_eq_eq, // !==
    lt,
    gt,
    lt_eq,
    gt_eq,
    ampersand_ampersand,
    pipe_pipe,
    lt_lt,
    gt_gt,
    arrow, // ->
    fat_arrow, // =>
    question,

    // delimiters
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    comma,
    semicolon,
    colon,
    dot,
    at,
    hash,

    // special
    eof,
    invalid,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

pub const Lexer = struct {
    source: []const u8,
    start: usize,
    current: usize,
    line: usize,
    column: usize,
    start_column: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .start = 0,
            .current = 0,
            .line = 1,
            .column = 1,
            .start_column = 1,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.isAtEnd()) {
            return self.makeToken(.eof);
        }

        self.start = self.current;
        self.start_column = self.column;

        const c = self.advance();

        if (isAlpha(c)) {
            return self.identifier();
        }

        if (isDigit(c)) {
            return self.number();
        }

        return switch (c) {
            '(' => self.makeToken(.lparen),
            ')' => self.makeToken(.rparen),
            '{' => self.makeToken(.lbrace),
            '}' => self.makeToken(.rbrace),
            '[' => self.makeToken(.lbracket),
            ']' => self.makeToken(.rbracket),
            ',' => self.makeToken(.comma),
            ';' => self.makeToken(.semicolon),
            ':' => self.makeToken(.colon),
            '.' => self.makeToken(.dot),
            '@' => self.makeToken(.at),
            '#' => self.makeToken(.hash),
            '~' => self.makeToken(.tilde),
            '?' => self.makeToken(.question),
            '+' => self.makeToken(.plus),
            '%' => self.makeToken(.percent),
            '^' => self.makeToken(.caret),
            '*' => self.makeToken(.star),
            '/' => self.makeToken(.slash),
            '-' => if (self.match('>')) self.makeToken(.arrow) else self.makeToken(.minus),
            '=' => if (self.match('=')) {
                if (self.match('=')) {
                    return self.makeToken(.eq_eq_eq);
                }
                return self.makeToken(.invalid);
            } else if (self.match('>')) {
                return self.makeToken(.fat_arrow);
            } else {
                return self.makeToken(.eq);
            },
            '!' => if (self.match('=')) {
                if (self.match('=')) {
                    return self.makeToken(.bang_eq_eq);
                }
                return self.makeToken(.invalid);
            } else {
                return self.makeToken(.bang);
            },
            '<' => if (self.match('=')) self.makeToken(.lt_eq) else if (self.match('<')) self.makeToken(.lt_lt) else self.makeToken(.lt),
            '>' => if (self.match('=')) self.makeToken(.gt_eq) else if (self.match('>')) self.makeToken(.gt_gt) else self.makeToken(.gt),
            '&' => if (self.match('&')) self.makeToken(.ampersand_ampersand) else self.makeToken(.ampersand),
            '|' => if (self.match('|')) self.makeToken(.pipe_pipe) else self.makeToken(.pipe),
            '"' => self.string(),
            '\'' => self.charLiteral(),
            else => self.makeToken(.invalid),
        };
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }

    fn peek(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        self.current += 1;
        self.column += 1;
        return true;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                },
                '\n' => {
                    self.line += 1;
                    self.column = 0;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        // line comment
                        while (self.peek() != '\n' and !self.isAtEnd()) {
                            _ = self.advance();
                        }
                    } else if (self.peekNext() == '*') {
                        // block comment
                        _ = self.advance();
                        _ = self.advance();
                        while (!self.isAtEnd()) {
                            if (self.peek() == '*' and self.peekNext() == '/') {
                                _ = self.advance();
                                _ = self.advance();
                                break;
                            }
                            if (self.peek() == '\n') {
                                self.line += 1;
                                self.column = 0;
                            }
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn makeToken(self: *const Lexer, token_type: TokenType) Token {
        return .{
            .type = token_type,
            .lexeme = self.source[self.start..self.current],
            .line = self.line,
            .column = self.start_column,
        };
    }

    fn identifier(self: *Lexer) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) {
            _ = self.advance();
        }
        return self.makeToken(self.identifierType());
    }

    fn identifierType(self: *const Lexer) TokenType {
        const text = self.source[self.start..self.current];

        // keyword lookup
        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "const", .const_kw },
            .{ "var", .var_kw },
            .{ "function", .function_kw },
            .{ "return", .return_kw },
            .{ "defer", .defer_kw },
            .{ "inout", .inout_kw },
            .{ "import", .import_kw },
            .{ "export", .export_kw },
            .{ "package", .package_kw },
            .{ "type", .type_kw },
            .{ "role", .role_kw },
            .{ "domain", .domain_kw },
            .{ "effects", .effects_kw },
            .{ "capability", .capability_kw },
            .{ "with", .with_kw },
            .{ "context", .context_kw },
            .{ "match", .match_kw },
            .{ "if", .if_kw },
            .{ "else", .else_kw },
            .{ "for", .for_kw },
            .{ "while", .while_kw },
            .{ "break", .break_kw },
            .{ "continue", .continue_kw },
            .{ "comptime", .comptime_kw },
            .{ "derivation", .derivation_kw },
            .{ "use", .use_kw },
            .{ "error", .error_kw },
            .{ "as", .as_kw },
            .{ "where", .where_kw },
            .{ "asm", .asm_kw },
            .{ "component", .component_kw },
            .{ "in", .in_kw },
            .{ "using", .using_kw },
            .{ "ok", .ok_kw },
            .{ "err", .err_kw },
            .{ "check", .check_kw },
            .{ "ensure", .ensure_kw },
            .{ "map_error", .map_error_kw },
            .{ "cap", .cap_kw },
            .{ "true", .true_kw },
            .{ "false", .false_kw },
            .{ "null", .null_kw },
        });

        return keywords.get(text) orelse .identifier;
    }

    fn number(self: *Lexer) Token {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        // fractional part
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(.number);
    }

    fn string(self: *Lexer) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 0;
            }
            if (self.peek() == '\\') {
                _ = self.advance();
                if (!self.isAtEnd()) {
                    _ = self.advance();
                }
            } else {
                _ = self.advance();
            }
        }

        if (self.isAtEnd()) {
            return self.makeToken(.invalid);
        }

        _ = self.advance(); // closing "
        return self.makeToken(.string);
    }

    fn charLiteral(self: *Lexer) Token {
        if (self.peek() == '\\') {
            _ = self.advance();
        }
        if (!self.isAtEnd()) {
            _ = self.advance();
        }

        if (self.peek() != '\'') {
            return self.makeToken(.invalid);
        }

        _ = self.advance(); // closing '
        return self.makeToken(.char);
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
