# Loops

Patapim provides several loop constructs for repetitive operations, each with distinct characteristics and use cases.

## 1. Infinite Loop (loop)
```
loop {
    // Code executes indefinitely
    if (exitCondition) break;
}
```

**Key Features:**

- Runs indefinitely until break is called
- Requires explicit exit condition

**Example:**
```
brr counter = 0;
loop {
    counter++;
    if (counter >= 100) break;
}
```

## 2. While Loop
```
while (condition) {
    // Code executes while condition is truthy
}
```

**Key Features:**

- Checks condition before each iteration
- May execute zero times if condition is initially falsy
- Preferred when iteration count is unknown

**Example:**

```
brr i = 0;
while (i < 5) {
    print(i);
    i += 1;
}
```

## 3. For Loop (Collections)
```
for (element in collection) {
    // Code executes for each element
}
```

**Key Features:**

- Iterates over arrays, strings, and other iterables
- Provides direct element access (not index)
- Clean syntax for collection processing

**Example:**
```
brr fruits = ["apple", "banana", "cherry"];
for (fruit in fruits) {
    ...
}
```

## 4. For Loop (Range-Based)
```
for (i in start..end) {
    // Code executes for each value in range
}
```

**Key Features:**

- Exclusive range (includes only start)
- Step size is always +1
- Similar to traditional for loops in other languages

**Example:**
```
for (i in 0..4) {
    print(i * 2);  // 0, 2, 4, 6, 8
}
```

## Loop Control Statements
### `break`
- Immediately exits the innermost loop
- Can be used in all loop types
- Often paired with conditional checks

**Example:**

```
while (true) {
    brr input = getInput();
    if (input == "quit") break;
}
```
---

### `continue`
- Skips to the next iteration
- Bypasses remaining code in current iteration
- Useful for filtering items

**Example:**
```
for (num in 1..10) {
    if (num % 2 == 0) continue;
    print(num);  // Only odd numbers
}
```