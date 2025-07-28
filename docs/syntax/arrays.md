# Arrays

Arrays are ordered collections that can hold elements of any type, including mixed types. They are dynamic in size and provide various built-in operations.

## Array Creation
```
// Empty array
brr empty = [];

// Array with initial values
brr numbers = [1, 2, 3];

// Mixed-type array
brr mixed = [1, "two", true, (1, 2, 3)];
```

## Basic Operations
### Accessing Elements
```
brr fruits = ["apple", "banana", "cherry"];
brr first = fruits[0];  // "apple" (zero-indexed)
brr last = fruits[fruits.len - 1];  // "cherry"
```

### Modifying Arrays
```
brr colors = ["red", "green"];
colors[1] = "blue";  // ["red", "blue"]
```

### Adding elements
```
colors.push("yellow");  // ["red", "blue", "yellow"]
colors.unshift("purple");  // ["purple", "red", "blue", "yellow"]
```

## Array Properties
### len (length)
```
brr arr = [1, 2, 3];
brr length = arr.len;  // 3 (equivalent to arr.length in some languages)
```