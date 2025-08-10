# Tuples

Tuples are fixed-size, immutable, ordered collections that can contain elements of different types. They provide a lightweight way to group related values without creating a formal structure.

## Tuple Creation
```
// Basic tuple
brr coordinates = (10, 20);

// Mixed-type tuple
brr userInfo = ("Alice", 30, true);

// Single-element tuple (note trailing comma)
brr single = ("only",);
```

## Accessing Elements
Tuples use zero-based indexing with dot notation:

```
brr person = ("Bob", 42, "Engineer");

brr name = person.0;    // "Bob"
brr age = person.1;     // 42
brr job = person.2;    // "Engineer"
```

**Tuple Characteristics:**

- Immutable Size: Cannot add or remove elements after creation
- Heterogeneous: Can contain different types in one tuple
- Ordered: Elements maintain their position
- Lightweight: More efficient than `struct` for simple groupings

## Common Use Cases
### 1. Multiple Return Values
```
fn getStats() {
    return (100, 85.5, "good"); // (count, average, status)
}

brr stats = getStats();
```

### 2. Fixed-Position Data
```
// RGB color
brr red = (255, 0, 0);

// Date components
brr date = (2025, 7, 28);
```

### 3. Pairing Values
```
brr keyValue = ("username", "alice123");
brr minMax = (0, 100);
```