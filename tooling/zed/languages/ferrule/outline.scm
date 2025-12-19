; functions appear in the outline
(function_declaration
  name: (identifier) @name) @item

; type declarations
(type_declaration
  name: (type_identifier) @name) @item

; domain declarations
(domain_declaration
  name: (type_identifier) @name) @item

; error declarations
(error_declaration
  name: (type_identifier) @name) @item

; capability declarations
(capability_declaration
  name: (type_identifier) @name) @item

; component declarations
(component_declaration
  name: (type_identifier) @name) @item

; top-level constants
(const_declaration
  name: (identifier) @name) @item
