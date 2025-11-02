# Variables and Constants

Patapim provides two ways to store values, with clear distinctions between mutable and immutable declarations. Using *camelCase* for variables is good practice in Patapim.

## Variable Declaration (brr)
```
brr myVar = 10;          // Basic declaration
brr name = "Patapim";    // String variable
brr isActive = true;     // Boolean variable
brr values = [1, 2, 3];  // Array variable
```

**Key Characteristics:**

- Mutable: Values can be changed after declaration
- Must Be Initialized: Requires value at declaration time
- Dynamically Typed: Type is inferred from the assigned value
- Block Scoped: Variables exist within their declaration block
- Reassignable: Can be modified multiple times
- `brr` stands for *briefly register resource*

**Usage Examples:**
```
brr counter = 0;          // Initialize
counter = counter + 1;    // Modify
```

## Constant Declaration (const)
```
const maxUsers = 100;
const pi = 3.14159;
const appName = "Patapim Runtime";
```

**Key Characteristics:**

- Immutable: Cannot be reassigned after declaration
- Must Be Initialized: Requires value at declaration time
- Block Scoped: Same scope rules as variables

**Usage Examples:**
```
const apiKey = "abc123-def456";
const daysInWeek = 7;

daysInWeek = 8;  // Would cause error - can't reassign const
```