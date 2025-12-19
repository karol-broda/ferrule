; indent after opening braces
[
  (block)
  (record_type)
  (record_body)
  (record_expression)
  (array_expression)
  (match_statement)
  (match_expression)
] @indent

; dedent on closing braces
[
  "}"
  "]"
  ")"
] @outdent
