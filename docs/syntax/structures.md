# Structures

Structures are user-defined types that group named fields and methods together. They provide type-safe data organization with attached behavior.

## Structure Creation
```
// Basic structure definition
struct Point {
    x,
    y,

    fn sum() {
        return this.x + this.y;
    }
}


// Instantiation
brr p = Point { x: 10, y: 20 }
```

**Structure Characteristics:**

- Named Fields: Elements accessed by name instead of position
- Mutable: Fields can be modified after creation (if not constant)
- Methods: Can contain attached functions
- Type-Safe: Enforces field types on assignment

## Accessing Elements
Structures use dot notation with field names:

```
brr point = Point { x: 5, y: 12 }

// Field access
brr x = point.x;       // 5
point.y = 20;          // Modification

// Method call
brr sum = point.sum(); // 25 (5 + 20)
```


## Common Use Cases
### 1. Complex Data Entities
```
struct User {
    name,
    age,
    isActive,

    fn activate() {
        this.isActive = true;
    }
}
```

### 2. Mathematical Objects
```
struct Vec3 {
    x, y, z,

    fn dot(other) {
        return this.x*other.x + this.y*other.y + this.z*other.z;
    }
}
```

### 3. Stateful Operations
```
struct Counter {
    count,

    fn increment() {
        this.count += 1;
    }
}

brr c = Counter { count: 0 };
c.increment();
```

## Comparison with Tuples
| Feature        | Tuples               | Structures          |
|----------------|----------------------|---------------------|
| Element Access | Positional (value.0) | Named (value.field) |
| Mutability     | Immutable❌         | Mutable✅           |
| Methods        | No❌                | Yes✅               |
| Use Case       | Temporary groupings  | Domain entities     |