; scopes
(function_declaration) @local.scope
(anonymous_function) @local.scope
(block) @local.scope
(for_statement) @local.scope
(while_statement) @local.scope
(if_statement) @local.scope
(match_arm) @local.scope

; definitions
(function_declaration
  name: (identifier) @local.definition.function)

(parameter
  name: (identifier) @local.definition.parameter)

(const_declaration
  name: (identifier) @local.definition.var)

; references
(identifier) @local.reference
