# Conditionals

Patapim provides flexible conditional statements to control program flow based on boolean expressions.

## Basic If-Else Structure
```
if (condition) {
    // Executes when condition is truthy
} else if (another_condition) {
    // Executes when first condition is falsy 
    // and another_condition is truthy
} else {
    // Executes when all conditions are falsy
}
```

**Key Characteristics:**

- Conditions can be any expression that evaluates to a boolean
- `else if` and `else` blocks are optional
- Braces `{}` are required for block bodies
- Supports nested conditionals

**Example Usage:**
```
if (temperature > 30) {
    showAlert("Hot day!");
} else if (temperature < 10) {
    showAlert("Cold day!");
} else {
    showAlert("Pleasant weather!");
}
```

### Single-Line If Statement
```
if (condition) { single_statement };
```

**Characteristics:** Braces needed even for single statements

## Inline Conditional (Ternary-style)
```
value = if (condition) value_if_true else value_if_false;
```

**Key Points:**

- Returns one of two values based on condition
- More concise than full if-else blocks

**Examples:**
```
// Assigning based on condition
brr status = if (score >= 50) "Pass" else "Fail";
```

```
// Returning from function
fn getDiscount(isMember, price) {
    return price*(if (isMember) 0.2 else 0.1);
}
```

## Truthy and Falsy Values
Patapim evaluates conditions using truthy/falsy rules:

**Falsy values:**

- `false`
- `0`
- `0.0`
- `""` (empty string)
- `[]` (empty array)
- any value of other type

**Truthy values:**

All other values are considered truthy