; keywords - control flow
[
  "if"
  "else"
  "match"
  "for"
  "while"
  "break"
  "continue"
  "return"
  "defer"
  "in"
] @keyword

; keywords - declarations
[
  "const"
  "var"
  "function"
  "type"
  "error"
  "domain"
  "capability"
  "component"
] @keyword

; keywords - modifiers
[
  "pub"
  "inout"
  "cap"
  "readonly"
] @keyword

; keywords - imports/modules
[
  "package"
  "import"
  "use"
  "as"
] @keyword

; keywords - effects/errors
[
  "effects"
  "ok"
  "err"
  "check"
] @keyword

; keywords - type system
[
  "where"
  "is"
  "out"
] @keyword

; operators
[
  "+"
  "-"
  "*"
  "/"
  "%"
  "++"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "&&"
  "||"
  "!"
  "&"
  "|"
  "^"
  "~"
  "<<"
  ">>"
  "="
  "->"
  ".."
  "..="
] @operator

; punctuation - brackets
"(" @punctuation.bracket
")" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket

; punctuation - delimiters
[
  ";"
  ","
  "."
  ":"
] @punctuation.delimiter

; literals
(string_literal) @string
(char_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean
"null" @constant.builtin
"Unit" @constant.builtin

; comments
(line_comment) @comment
(block_comment) @comment

; types - builtin primitives
(primitive_type) @type.builtin

; types - user defined
(type_identifier) @type

; function definitions
(function_declaration
  name: (identifier) @function.definition)

; built-in function calls
(call_expression
  (identifier) @function.builtin
  (#match? @function.builtin "^(print|println|panic|assert|debug|len|size|capacity)$"))

; method calls: obj.method()
(call_expression
  (member_expression
    (identifier) @function.method))

; regular function calls
(call_expression
  (identifier) @function.call)

; anonymous functions / lambdas
(anonymous_function) @function

; variables - parameters
(parameter
  name: (identifier) @variable.parameter)

; variables - declarations
(const_declaration
  name: (identifier) @variable)

; domains and errors
(domain_declaration
  name: (type_identifier) @type)

(error_declaration
  name: (type_identifier) @type)

(error_variant
  (type_identifier) @constructor)

; type declarations
(type_declaration
  name: (type_identifier) @type)

; capability declarations
(capability_declaration
  name: (type_identifier) @type)

; component declarations  
(component_declaration
  name: (type_identifier) @type)

; union variants
(union_variant
  (type_identifier) @constructor)

; record fields
(record_field
  (identifier) @property)

; member access
(member_expression
  (identifier) @property)

; package path
(package_path
  (identifier) @module)

; patterns
(pattern
  (identifier) @variable)

"_" @variable.builtin

(destructuring_pattern
  (type_identifier) @constructor)

; for loop variable
(for_statement
  (identifier) @variable)

; generic types
(generic_type
  (type_identifier) @type)

; identifiers (fallback)
(identifier) @variable
