# Closures

Closures are self-contained blocks of functionality that can capture and store references to variables from their surrounding context. They combine function behavior with environment capture.

## Basic Closure Syntax
```
// Simple closure
brr greet = () -> {
    return "Hello there";
}

// Multi-parameter closure
brr add = (a, b) -> {
    return a + b;
}

brr result = add(1, 3); // 4
```

**Key Features:**

- Environment Capture:
```
brr result = 10;
brr addToResult = (value) -> {
    return prefix + value; // Captures 'result' from outer scope
}
```