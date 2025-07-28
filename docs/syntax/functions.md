# Functions
Functions are fundamental building blocks in Patapim that encapsulate reusable pieces of code. They help organize logic, reduce repetition, and make programs more maintainable.

## Basic Function Declaration
```
fn functionName(parameter1, parameter2) {
    // Function body
    return result; // Optional return
}
```

**Key Characteristics:**

- Declared with the fn keyword
- Function names use *camelCase* convention
- Can accept zero or more parameters
- Can optionally return a value using `return`
- Return type is dynamically determined

## Function Components

### 1. Parameters
```
fn add(a, b) {
    return a + b;
}
```

- Parameters are passed by value
- No type annotations required (dynamic typing)

### 2. Return Values
```
fn sub(a, b) {
    return a - b; // Explicit return
}
```

### 3. Call Functions
```
brr result = sub(5, 2);
```