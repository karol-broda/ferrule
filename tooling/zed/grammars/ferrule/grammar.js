/**
 * @file Ferrule language grammar for tree-sitter
 * @author Karol Broda <me@karolbroda.com>
 * @license MIT
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const PREC = {
  ASSIGN: 1,
  OR: 2,
  AND: 3,
  EQUALITY: 4,
  COMPARE: 5,
  BIT_OR: 6,
  BIT_XOR: 7,
  BIT_AND: 8,
  SHIFT: 9,
  ADD: 10,
  MULT: 11,
  UNARY: 12,
  CALL: 13,
  MEMBER: 14,
};

module.exports = grammar({
  name: "ferrule",

  extras: ($) => [/\s/, $.line_comment, $.block_comment],

  word: ($) => $.identifier,

  inline: ($) => [$._type_identifier],

  conflicts: ($) => [
    [$.match_statement, $.match_expression],
    [$.if_statement, $.if_expression],
  ],

  rules: {
    source_file: ($) =>
      seq(optional($.package_declaration), repeat($._top_level_item)),

    _top_level_item: ($) =>
      choice(
        $.function_declaration,
        $.type_declaration,
        $.domain_declaration,
        $.error_declaration,
        $.use_declaration,
        $.import_declaration,
        $.const_declaration,
        $.capability_declaration,
        $.component_declaration
      ),

    // comments
    line_comment: ($) => token(seq("//", /[^\n]*/)),
    block_comment: ($) => token(seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/")),

    // identifiers
    identifier: ($) => /[a-z_][a-zA-Z0-9_]*/,
    _type_identifier: ($) => alias(/[A-Z][a-zA-Z0-9_]*/, $.type_identifier),

    // package declaration
    package_declaration: ($) =>
      seq("package", field("path", $.package_path), ";"),

    package_path: ($) => sep1($.identifier, "."),

    // imports
    import_declaration: ($) =>
      seq("import", field("path", $.package_path), optional(seq("as", $.identifier)), ";"),

    // use declarations
    use_declaration: ($) =>
      seq("use", "error", $._type_identifier, ";"),

    // function declarations
    function_declaration: ($) =>
      seq(
        optional("pub"),
        "function",
        field("name", $.identifier),
        optional($.type_parameters),
        field("parameters", $.parameter_list),
        "->",
        field("return_type", $._type),
        optional($.error_clause),
        optional($.effects_clause),
        field("body", $.block)
      ),

    parameter_list: ($) =>
      seq("(", commaSep($.parameter), ")"),

    parameter: ($) =>
      seq(
        optional(choice("inout", "cap")),
        field("name", $.identifier),
        ":",
        field("type", $._type)
      ),

    error_clause: ($) => seq("error", $._type_identifier),

    effects_clause: ($) => seq("effects", "[", commaSep($.identifier), "]"),

    type_parameters: ($) =>
      seq("<", commaSep1($.type_parameter), ">"),

    type_parameter: ($) =>
      seq(
        optional(choice("in", "out")),
        field("name", $._type_identifier)
      ),

    // type declarations
    type_declaration: ($) =>
      seq(
        optional("pub"),
        "type",
        field("name", $._type_identifier),
        optional($.type_parameters),
        "=",
        field("type", $._type),
        optional(seq("where", $._expression)),
        ";"
      ),

    // domain declarations
    domain_declaration: ($) =>
      choice(
        // union syntax: domain D = A | B;
        seq(
          optional("pub"),
          "domain",
          field("name", $._type_identifier),
          "=",
          sep1($._type_identifier, "|"),
          ";"
        ),
        // inline syntax: domain D { A { } B { } }
        seq(
          optional("pub"),
          "domain",
          field("name", $._type_identifier),
          "{",
          repeat($.error_variant),
          "}"
        )
      ),

    error_variant: ($) =>
      seq($._type_identifier, optional($.record_body)),

    // error declarations
    error_declaration: ($) =>
      seq(
        optional("pub"),
        "error",
        field("name", $._type_identifier),
        choice($.record_body, ";")
      ),

    // capability declarations
    capability_declaration: ($) =>
      seq(
        optional("pub"),
        "capability",
        field("name", $._type_identifier),
        "{",
        repeat(seq($.identifier, ":", $._type, optional(";"))),
        "}"
      ),

    // component declarations
    component_declaration: ($) =>
      seq(
        optional("pub"),
        "component",
        field("name", $._type_identifier),
        "{",
        repeat(choice($.function_declaration, $.type_declaration)),
        "}"
      ),

    // const/var declarations
    const_declaration: ($) =>
      seq(
        choice("const", "var"),
        field("name", $.identifier),
        optional(seq(":", $._type)),
        "=",
        field("value", $._expression),
        ";"
      ),

    // types
    _type: ($) =>
      choice(
        $._simple_type,
        $.generic_type,
        $.function_type,
        $.record_type,
        $.union_type
      ),

    _simple_type: ($) =>
      choice(
        $._type_identifier,
        $.primitive_type
      ),

    primitive_type: ($) =>
      choice(
        "i8", "i16", "i32", "i64", "i128",
        "u8", "u16", "u32", "u64", "u128", "usize",
        "f16", "f32", "f64",
        "Bool", "Char", "String", "Bytes", "Unit", "Never"
      ),

    generic_type: ($) =>
      seq($._type_identifier, "<", commaSep1($._type), ">"),

    function_type: ($) =>
      seq("(", commaSep($._type), ")", "->", $._type),

    record_type: ($) =>
      seq("{", commaSep($.record_field), "}"),

    record_body: ($) =>
      seq("{", commaSep($.record_field), "}"),

    record_field: ($) =>
      seq(optional("readonly"), $.identifier, ":", $._type),

    union_type: ($) =>
      seq("|", sep1($.union_variant, "|")),

    union_variant: ($) =>
      prec.right(seq($._type_identifier, optional($.record_body))),

    // statements
    _statement: ($) =>
      choice(
        $.const_declaration,
        $.expression_statement,
        $.return_statement,
        $.if_statement,
        $.match_statement,
        $.for_statement,
        $.while_statement,
        seq("break", ";"),
        seq("continue", ";"),
        seq("defer", choice($.block, seq($._expression, ";"))),
        $.block
      ),

    expression_statement: ($) => seq($._expression, ";"),

    return_statement: ($) =>
      seq("return", optional($._expression), ";"),

    if_statement: ($) =>
      prec.right(seq(
        "if",
        field("condition", $._expression),
        field("consequence", $.block),
        optional(seq("else", field("alternative", choice($.block, $.if_statement))))
      )),

    match_statement: ($) =>
      seq("match", $._expression, "{", repeat($.match_arm), "}"),

    match_arm: ($) =>
      seq(
        $.pattern,
        optional(seq("if", $._expression)),
        "->",
        choice($._expression, $.block),
        optional(";")
      ),

    pattern: ($) =>
      choice(
        $.identifier,
        $._type_identifier,
        $._literal,
        "_",
        $.destructuring_pattern
      ),

    destructuring_pattern: ($) =>
      seq(optional($._type_identifier), "{", commaSep($.identifier), "}"),

    for_statement: ($) =>
      seq("for", $.identifier, "in", $._expression, $.block),

    while_statement: ($) =>
      seq("while", $._expression, $.block),

    block: ($) => seq("{", repeat($._statement), "}"),

    // expressions
    _expression: ($) =>
      choice(
        $._primary_expression,
        $.unary_expression,
        $.binary_expression,
        $.call_expression,
        $.member_expression,
        $.index_expression,
        $.record_expression,
        $.array_expression,
        $.parenthesized_expression
      ),

    _primary_expression: ($) =>
      choice(
        $.identifier,
        $._type_identifier,
        $._literal,
        $.if_expression,
        $.match_expression,
        $.anonymous_function,
        $.ok_expression,
        $.err_expression,
        $.check_expression
      ),

    _literal: ($) =>
      choice(
        $.integer_literal,
        $.float_literal,
        $.string_literal,
        $.char_literal,
        $.boolean_literal,
        "null",
        "Unit"
      ),

    integer_literal: ($) =>
      token(choice(
        /[0-9][0-9_]*/,
        /0x[0-9a-fA-F][0-9a-fA-F_]*/,
        /0b[01][01_]*/,
        /0o[0-7][0-7_]*/
      )),

    float_literal: ($) =>
      token(/[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?/),

    string_literal: ($) =>
      seq('"', repeat(choice($.escape_sequence, /[^"\\]+/)), '"'),

    char_literal: ($) =>
      seq("'", choice($.escape_sequence, /[^'\\]/), "'"),

    escape_sequence: ($) => token(/\\[nrt\\'"0]/),

    boolean_literal: ($) => choice("true", "false"),

    unary_expression: ($) =>
      prec(PREC.UNARY, seq(choice("-", "!", "~"), $._expression)),

    binary_expression: ($) => {
      const ops = [
        [PREC.OR, "||"],
        [PREC.AND, "&&"],
        [PREC.EQUALITY, choice("==", "!=")],
        [PREC.COMPARE, choice("<", "<=", ">", ">=", "is")],
        [PREC.BIT_OR, "|"],
        [PREC.BIT_XOR, "^"],
        [PREC.BIT_AND, "&"],
        [PREC.SHIFT, choice("<<", ">>")],
        [PREC.ADD, choice("+", "-", "++", "..", "..=")],
        [PREC.MULT, choice("*", "/", "%")],
        [PREC.ASSIGN, "="],
      ];
      return choice(
        ...ops.map(([p, op]) =>
          prec.left(p, seq($._expression, op, $._expression))
        )
      );
    },

    call_expression: ($) =>
      prec(PREC.CALL, seq($._expression, "(", commaSep($._expression), ")")),

    member_expression: ($) =>
      prec(PREC.MEMBER, seq($._expression, ".", $.identifier)),

    index_expression: ($) =>
      prec(PREC.MEMBER, seq($._expression, "[", $._expression, "]")),

    parenthesized_expression: ($) => seq("(", $._expression, ")"),

    if_expression: ($) =>
      prec.right(seq(
        "if", $._expression, $.block,
        "else", choice($.block, $.if_expression)
      )),

    match_expression: ($) =>
      seq("match", $._expression, "{", repeat($.match_arm), "}"),

    anonymous_function: ($) =>
      seq(
        "function",
        optional($.type_parameters),
        $.parameter_list,
        "->",
        $._type,
        optional($.error_clause),
        optional($.effects_clause),
        $.block
      ),

    record_expression: ($) =>
      prec(PREC.MEMBER, seq(
        optional($._type_identifier),
        "{",
        commaSep(seq($.identifier, ":", $._expression)),
        "}"
      )),

    array_expression: ($) =>
      seq("[", commaSep($._expression), "]"),

    ok_expression: ($) =>
      prec.right(PREC.UNARY, seq("ok", $._expression)),

    err_expression: ($) =>
      prec.right(PREC.UNARY, seq("err", $._type_identifier, optional($.record_expression))),

    check_expression: ($) =>
      prec.right(PREC.UNARY, seq("check", $._expression)),
  },
});

function commaSep(rule) {
  return optional(commaSep1(rule));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(",", rule)), optional(","));
}

function sep1(rule, separator) {
  return seq(rule, repeat(seq(separator, rule)));
}
