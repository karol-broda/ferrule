; functions
(function_declaration
  name: (identifier) @name) @definition.function

; types
(type_declaration
  name: (type_identifier) @name) @definition.type

; domains
(domain_declaration
  name: (type_identifier) @name) @definition.type

; errors
(error_declaration
  name: (type_identifier) @name) @definition.type

; capabilities
(capability_declaration
  name: (type_identifier) @name) @definition.interface

; components
(component_declaration
  name: (type_identifier) @name) @definition.module

; constants
(const_declaration
  name: (identifier) @name) @definition.constant

; function calls
(call_expression
  (identifier) @name) @reference.call
