; function text objects for vim mode
(function_declaration
  body: (block) @function.inside) @function.around

(anonymous_function
  (block) @function.inside) @function.around

; class-like text objects (domains, capabilities, components)
(domain_declaration) @class.around
(capability_declaration) @class.around
(component_declaration) @class.around

; comment text objects
(line_comment)+ @comment.around
(block_comment) @comment.around
