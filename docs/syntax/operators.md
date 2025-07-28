# Operators

Patapim provides a comprehensive set of operators for performing operations on variables and values. These operators follow conventional precedence rules and include some language-specific behaviors.

## Operator Categories
### 1. Arithmetic Operators
```
+   Addition        (5 + 3 → 8)
-   Subtraction     (5 - 3 → 2)
*   Multiplication  (5 * 3 → 15)
/   Division        (6 / 3 → 2)
%   Modulus         (5 % 3 → 2)
++  Increment       (x++ → x + 1)
--  Decrement       (x-- → x - 1)
```

**++/-- can only be postfix.**

### 2. Comparison Operators
```
==  Equal to              (5 == 5 → true)
!=  Not equal             (5 != 3 → true)
>   Greater than          (5 > 3 → true)
<   Less than             (5 < 3 → false)
>=  Greater or equal      (5 >= 5 → true)
<=  Less or equal         (5 <= 3 → false)
```

### 3. Logical Operators
```
&&/and  Logical AND          (true && false → false)
||/or  Logical OR           (true || false → true)
!   Logical NOT          (!true → false)
```

### 4. Bitwise Operators
```
&   AND          (5 & 3 → 1)
|   OR           (5 | 3 → 7)
^   XOR          (5 ^ 3 → 6)
~   NOT          (~5 → -6)
<<  Left shift   (5 << 1 → 10)
>>  Right shift  (5 >> 1 → 2)
```

### 5. Assignment Operators
```
=   Simple assignment    (x = 5)
+=  Add and assign       (x += 3 → x = x + 3)
-=  Subtract and assign  (x -= 2)
*=  Multiply and assign  (x *= 4)
/=  Divide and assign    (x /= 2)
%=  Modulo and assign    (x %= 3)
```

### 6. Other Operators
```
.   Member access      (user.name)
[]  Index access       (array[0])
()  Function call      (myFunction())
..  Range              (for i in 1..5)
```