# Grammar (EBNF)

> **scope:** complete EBNF grammar for Ferrule α1  
> **related:** [keywords.md](keywords.md) | [operators.md](operators.md)

---

## Notation

- `|` alternation
- `?` optional (zero or one)
- `*` zero or more
- `+` one or more
- `{ }` grouping
- `"..."` terminal string
- `/* ... */` comment

---

## Lexical

```ebnf
Identifier   := Letter { Letter | Digit | "_" }
Letter       := /* unicode letter or _ */
Digit        := "0"…"9"

Number       := IntLit | FloatLit
IntLit       := Digit+ | "0x" HexDigit+ | "0b" BinDigit+ | "0o" OctDigit+
FloatLit     := Digit+ "." Digit+ { "e" ["+"|"-"] Digit+ }?

StringLit    := '"' { StringChar }* '"'
StringChar   := /* any char except " or \, or escape sequence */

BoolLit      := "true" | "false"
BytesLit     := 'b"' { ByteChar }* '"'

Comment      := "//" { any }* newline
             | "/*" { any }* "*/"
```

---

## Module Structure

```ebnf
Module       := PackageDecl { ImportDecl }* { TopDecl }*

PackageDecl  := "package" QualifiedName ";"
QualifiedName:= Identifier { "." Identifier }*

ImportDecl   := "import" ImportSource "{" ImportList "}"
                { "with" "{" SettingList "}" }?
                { "using" "capability" Identifier }? ";"

ImportSource := QualifiedName 
             | "store://" Hash
             | "@import" "(" StringLit ")"

ImportList   := Identifier { "," Identifier }* { "as" Identifier }?

SettingList  := Setting { "," Setting }*
Setting      := Identifier ":" Value
```

---

## Top-Level Declarations

```ebnf
TopDecl      := TypeDecl 
             | ErrorDecl
             | DomainDecl 
             | FunctionDecl 
             | ConstDecl
             | UseDecl

TypeDecl     := "type" Identifier { "<" TypeParams ">" }? "=" TypeExpr ";"

ErrorDecl    := "error" Identifier { "{" FieldList "}" }? ";"

DomainDecl   := "domain" Identifier "=" ErrorUnion ";"    /* union syntax */
             | "domain" Identifier "{" { DomainVariant }* "}"  /* inline variant syntax */

ErrorUnion   := Identifier { "|" Identifier }*

DomainVariant := Identifier { "{" FieldList "}" }?

ConstDecl    := "const" QualifiedIdent ":" TypeExpr "=" Expr ";"
QualifiedIdent := Identifier { "." Identifier }?

UseDecl      := "use" "error" Identifier ";"
```

---

## Functions

```ebnf
FunctionDecl := { "export" { "c" | "wasm" }? }?
                { "pub" }?
                "function" Identifier 
                { "<" TypeParams ">" }?
                "(" ParamList? ")" 
                "->" TypeExpr
                { "error" ErrorType }?
                { "effects" "[" EffectList? "]" }?
                { WhereClause }?
                Block

ParamList    := Param { "," Param }*
Param        := { "cap" }? { "inout" }? Identifier ":" TypeExpr

EffectList   := EffectItem { "," EffectItem }*
EffectItem   := Identifier | "..." | "..." Identifier

ErrorType    := Identifier 
             | "(" ErrorUnion ")"
             | "Pick" "<" Identifier "," ErrorUnion ">"
             | "Omit" "<" Identifier "," Identifier ">"

WhereClause  := "where" Constraint { "," Constraint }*
Constraint   := Identifier "includes" "[" EffectList "]"
             | Identifier "is" TypeExpr

TypeParams   := TypeParam { "," TypeParam }*
TypeParam    := { "in" | "out" }? Identifier { ":" TypeConstraint }?
             | "const" Identifier ":" TypeExpr
             | "..." Identifier
```

---

## Type Expressions

```ebnf
TypeExpr     := SimpleType { TypeOp }*

SimpleType   := Identifier { "<" TypeArgs ">" }?
             | "{" FieldList "}"
             | "|" Variant { "|" Variant }*
             | "(" TypeExpr ")"
             | FunctionType
             | ConditionalType
             | MappedType
             | TemplateLitType

TypeOp       := "&" SimpleType              /* intersection */
             | "?"                           /* nullable */
             | "where" Predicate            /* refinement */

TypeArgs     := TypeArg { "," TypeArg }*
TypeArg      := TypeExpr | "infer" Identifier

FieldList    := Field { "," Field }*
Field        := Identifier ":" TypeExpr

Variant      := Identifier { "{" FieldList "}" }?

FunctionType := "(" { ParamTypeList }? ")" "->" TypeExpr 
                { "error" ErrorType }? 
                { "effects" "[" EffectList "]" }?

ParamTypeList := TypeExpr { "," TypeExpr }*

ConditionalType := "if" TypeExpr "is" TypeExpr "then" TypeExpr "else" TypeExpr

MappedType   := "map" TypeExpr "{" Identifier "=>" TypeExpr "}"

TemplateLitType := "`" { StringPart | "${" TypeExpr "}" }* "`"

/* built-in parametric types */
ArrayType    := "Array" "<" TypeExpr "," NatExpr ">"
VectorType   := "Vector" "<" TypeExpr "," NatExpr ">"
ViewType     := "View" "<" { "mut" }? TypeExpr ">"
```

---

## Statements

```ebnf
Block        := "{" { Statement }* "}"

Statement    := ConstDecl
             | VarDecl
             | ConstMatch
             | Assignment
             | If
             | IfMatch
             | While
             | WhileMatch
             | For
             | Match
             | MatchCheck
             | Return
             | Defer
             | ContextBlock
             | Expr ";"

LocalConstDecl := "const" Identifier { ":" TypeExpr }? "=" Expr ";"
VarDecl      := "var" Identifier ":" TypeExpr "=" Expr ";"
ConstMatch   := "const" Pattern "=" Expr "else" Block ";"
Assignment   := LValue "=" Expr ";"

If           := "if" Expr Block { "else" Block | IfMatch }?
IfMatch      := "if" "match" Expr "{" Case "}" { "else" Block }?
While        := "while" Expr Block
WhileMatch   := "while" "match" Expr "{" Case "}"
For          := "for" Identifier "in" Expr Block
Match        := "match" Expr "{" { Case }+ "}"
MatchCheck   := "match" "check" Expr "{" { Case }+ "}"
Return       := "return" Expr ";"
Defer        := "defer" Expr ";"

ContextBlock := "with" "context" "{" ContextList "}" "in" Block
ContextList  := ContextItem { "," ContextItem }*
ContextItem  := Identifier ":" Expr

Case         := Pattern { "where" Expr }? "->" Expr ";"
```

---

## Patterns

```ebnf
Pattern      := OrPattern

OrPattern    := NamedPattern { "|" NamedPattern }*

NamedPattern := Identifier "as" PrimaryPattern   /* named binding */
             | PrimaryPattern

PrimaryPattern := "_"                            /* wildcard */
             | Literal                           /* literal match */
             | RangePattern                      /* range match */
             | Identifier                        /* binding or unit variant */
             | Identifier "{" PatternFields "}"  /* variant/record destructure */
             | "{" PatternFields { "," ".." }? "}" /* record pattern */
             | ArrayPattern                      /* array pattern */
             | "(" Pattern ")"                   /* grouped */

RangePattern := RangeBound ".." RangeBound       /* exclusive range */
             | RangeBound "..=" RangeBound       /* inclusive range */

RangeBound   := IntLit | CharLit

ArrayPattern := "[" "]"                          /* empty */
             | "[" PatternList "]"               /* fixed elements */
             | "[" PatternList "," ".." "]"      /* prefix + rest */
             | "[" ".." "]"                      /* any length */
             | "[" ".." "," PatternList "]"      /* rest + suffix */
             | "[" PatternList "," ".." "," PatternList "]" /* prefix + rest + suffix */

PatternList  := Pattern { "," Pattern }*

PatternFields := PatternField { "," PatternField }*
PatternField  := Identifier { ":" Pattern }?
```

---

## Expressions

```ebnf
Expr         := Primary { Postfix | InfixOp Primary }*

Primary      := Literal
             | Identifier
             | "(" Expr ")"
             | Block
             | AnonFunction
             | "ok" Expr
             | "err" Identifier "{" FieldAssignments "}"
             | "check" Expr { "with" "{" ContextList "}" }?
             | "ensure" Expr "else" "err" Identifier "{" FieldAssignments "}"
             | "map_error" Expr "using" "(" Identifier "=>" Expr ")"
             | "comptime" Expr
             | "unsafe_cast" "<" TypeExpr ">" "(" Expr ")"
             | AsmExpr

AnonFunction := "function" "(" ParamList? ")" "->" TypeExpr Block

Postfix      := "(" ArgList? ")"            /* call */
             | "." Identifier               /* field access */
             | "[" Expr "]"                 /* index */

ArgList      := Expr { "," Expr }*

FieldAssignments := FieldAssign { "," FieldAssign }*
FieldAssign      := Identifier ":" Expr

Literal      := Number 
             | StringLit 
             | BoolLit 
             | BytesLit 
             | "null" 
             | "Unit"
             | ArrayLit
             | RecordLit

ArrayLit     := "[" { Expr { "," Expr }* }? "]"
             | "[" Expr ";" Expr "]"        /* [value; count] */

RecordLit    := "{" FieldAssignments "}"
```

---

## Inline Assembly

```ebnf
AsmExpr      := "asm" Identifier            /* target */
                "in" "{" AsmBindings "}"
                "out" "{" AsmBindings "}"
                "clobber" "[" ClobberList "]"
                { "volatile" }?
                StringLit ";"

AsmBindings  := { AsmBinding { "," AsmBinding }* }?
AsmBinding   := Identifier ":" TypeExpr "in" Identifier

ClobberList  := { Identifier { "," Identifier }* }?
```

---

## Operators (by precedence, low to high)

```ebnf
InfixOp      := "||"                        /* logical or */
             | "&&"                         /* logical and */
             | "==" | "!="                  /* equality (single ==, no ===) */
             | "<" | "<=" | ">" | ">="      /* comparison */
             | "|"                          /* bitwise or */
             | "^"                          /* bitwise xor */
             | "&"                          /* bitwise and */
             | "<<" | ">>"                  /* shift */
             | "++" | "+" | "-"             /* additive & string concat */
             | "*" | "/" | "%"              /* multiplicative */

PrefixOp     := "!" | "-" | "~"
```

**Note:** Ferrule uses `==` for equality (not `===`). See [operators.md](operators.md) for detailed precedence table.
