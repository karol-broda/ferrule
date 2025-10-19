current state:
```bash
➜ ./zig-out/bin/ferrule examples/hello.fe
=== compiling examples/hello.fe ===

lexed 114 tokens:
    1:  1      package_kw 'package'
    1:  9      identifier 'example'
    1: 16             dot '.'
    1: 17      identifier 'hello'
    1: 22       semicolon ';'
    3:  1       domain_kw 'domain'
    3:  8      identifier 'IoError'
    3: 16          lbrace '{'
    4:  3      identifier 'NotFound'
    4: 12          lbrace '{'
    4: 14      identifier 'path'
    4: 18           colon ':'
    4: 20      identifier 'String'
    4: 27          rbrace '}'
    5:  3      identifier 'Denied'
    5: 10          lbrace '{'
    5: 12      identifier 'path'
    5: 16           colon ':'
    5: 18      identifier 'String'
    5: 25          rbrace '}'
    6:  3      identifier 'Interrupted'
    6: 15          lbrace '{'
    6: 17      identifier 'op'
    6: 19           colon ':'
    6: 21      identifier 'String'
    6: 28          rbrace '}'
    7:  1          rbrace '}'
    9:  1          use_kw 'use'
    9:  5        error_kw 'error'
    9: 11      identifier 'IoError'
    9: 18       semicolon ';'
   11:  1     function_kw 'function'
   11: 10      identifier 'add'
   11: 13          lparen '('
   11: 14      identifier 'x'
   11: 15           colon ':'
   11: 17      identifier 'i32'
   11: 20           comma ','
   11: 22      identifier 'y'
   11: 23           colon ':'
   11: 25      identifier 'i32'
   11: 28          rparen ')'
   11: 30           arrow '->'
   11: 33      identifier 'i32'
   11: 37          lbrace '{'
   12:  3       return_kw 'return'
   12: 10      identifier 'x'
   12: 12            plus '+'
   12: 14      identifier 'y'
   12: 15       semicolon ';'
  ... and 64 more tokens

parsed successfully

=== semantic analysis ===


=== semantic errors ===

error: unknown type 'tring'
  ┌─ examples/hello.fe:15:22
  │
 15 │ function greet(name: tring) -> tring {
  │                      ^^^^^

error: unknown type 'tring'
  ┌─ examples/hello.fe:15:32
  │
 15 │ function greet(name: tring) -> tring {
  │                                ^^^^^

error: unknown type 'tring'
  ┌─ examples/hello.fe:15:22
  │
 15 │ function greet(name: tring) -> tring {
  │                      ^^^^^

error: return type mismatch: expected (), got String
  ┌─ examples/hello.fe:17:3
  │
 17 │   return greeting;
  │   ^^^^^^

error: return type mismatch: expected i32, got String
  ┌─ examples/hello.fe:26:5
  │
 26 │     return "0";
  │     ^^^^^^


=== compilation failed ===
```