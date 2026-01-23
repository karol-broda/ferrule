; function text objects
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

; parameter text objects
(parameter) @parameter.around

; block text objects
(block) @block.around
