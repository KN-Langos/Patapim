# Patapim lexer specification
This document describes how Patapim lexer should handle tokens.
Including (but not limited to) comments, whitespaces, keywords, operators.

## Token list
This token list may change in the future, but those are basic tokens
required for minimum viable Patapim interpreter.
Names are just examples, they can be changed in the implementation.
```python
# Parentheses
'(' LEFT_PAREN
')' RIGHT_PAREN
'{' LEFT_CURLY
'}' RIGHT_CURLY
'[' LEFT_SQUARE
']' RIGHT_SQUARE

# Boolean Operators
'==' EQ_EQ
'!=' NOT_EQ
'<'  LESS_THAN
'>'  GREATER_THAN
'<=' LESS_EQUAL
'>=' GREATER_EQUAL

# Logical and Bitwise Operators
'!'  BANG
'|'  BITWISE_OR
'&'  BITWISE_AND
'^'  BITWISE_XOR
'and'/'&&' LOGICAL_AND
'or'/'||'  LOGICAL_OR
'<<' BITSHIFT_LEFT
'>>' BITSHIFT_RIGHT

# Assignment Variants (Logical and Bitwise)
'|=' BITWISE_OR_ASSIGN
'&=' BITWISE_AND_ASSIGN
'^=' BITWISE_XOR_ASSIGN

# Math Operators
'+' ADD
'-' SUBTRACT
'*' MULTIPLY
'/' DIVIDE
'%' MODULO

# Assignment Variants (Math)
'+=' ADD_ASSIGN
'-=' SUB_ASSIGN
'*=' MUL_ASSIGN
'/=' DIV_ASSIGN
'%=' MOD_ASSIGN
'++' INCREMENT
'--' DECREMENT

# Special Symbols
';'   SEMICOLON
':'   COLON
'.'   DOT
'..'  RANGE
'...' SPREAD
'->'  ARROW
'@'   AT
'#'   HASH
'?'   QUESTION
'$'   DOLLAR

# Keywords
'import' KW_IMPORT
'as' KW_AS
'struct' KW_STRUCT
'enum' KW_ENUM
'true' KW_TRUE
'false' KW_FALSE
'if' KW_IF
'else' KW_ELSE
'return' KW_RETURN
'error' KW_ERROR
'loop' KW_LOOP
'while' KW_WHILE
'do' KW_DO
'for' KW_FOR
'in' KW_IN
'fn' KW_FUNCTION
'brr' KW_VARIABLE
'const' KW_CONST
'native' KW_NATIVE
'iserror' KW_ISERROR
```
