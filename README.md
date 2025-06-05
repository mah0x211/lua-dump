# lua-dump

[![test](https://github.com/mah0x211/lua-dump/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-dump/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-dump/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-dump)

A Lua library for converting data structures to readable string representations. Supports tables, nested structures, circular references, and custom formatting options.

---

## Installation

```bash
luarocks install dump
```


## API Reference

### str = dump( val [, indent [, padding [, filter [, udata ]]]])

Converts a Lua value to its string representation.

**Parameters**

- `val:any`: The value to be converted to string
- `indent:number`: Number of spaces for each indentation level (default: `4`)
- `padding:number`: Number of spaces to add at the beginning of each line (default: `0`)
- `filter:function`: Optional function to transform values during dumping (default: `nil`)
- `udata:any`: User data passed to the filter function (default: `nil`)

**Returns**

- `string`: The string representation of the input value

**Filter Function**

```lua
val, nodump = filter(val, depth, typ, use, key, udata)
```

**Parameters**

- `val:any`: The current value being processed
- `depth:number`: Current nesting depth (starts at 0)
- `typ:string`: Type of the value (`"nil"`, `"boolean"`, `"number"`, `"string"`, `"table"`, `"function"`, `"userdata"`, `"thread"`)
- `use:string`: Context of usage - `"key"`, `"val"`, or `"circular"`
- `key:any`: The key associated with this value (if applicable)
- `udata:any`: User data passed from the main dump call

**Returns**

- `val:any`: The transformed value to use instead of the original
- `nodump:boolean`: If `true`, skip dumping this value entirely (default: `false`)

**Examples**

```lua
local data = {x = 1, y = {a = 2, b = 3}}

-- Basic usage
print(dump(data))
-- {
--     x = 1,
--     y = {
--         a = 2,
--         b = 3
--     }
-- }

-- Custom indentation  
print(dump(data, 2))
-- {
--   x = 1,
--   y = {
--     a = 2,
--     b = 3
--   }
-- }

-- With padding
print(dump(data, 4, 2))
--  {
--        x = 1,
--        y = {
--            a = 2,
--            b = 3
--        }
--    }
```


## Quick Start

```lua
local dump = require('dump')

-- Basic usage
print(dump({name = "Alice", age = 25}))
-- Output: { age = 25, name = "Alice" }
```

## Usage Examples

### Basic Data Types

```lua
local dump = require('dump')

-- Primitive values
print(dump(nil))        --> "nil"
print(dump(true))       --> "true"  
print(dump(42))         --> "42"
print(dump("hello"))    --> "hello"
```

### Table Structures

```lua
local dump = require('dump')

-- Simple table
local person = {
    name = "John Doe",
    age = 30,
    active = true
}

print(dump(person))
-- Output:
-- {
--     active = true,
--     age = 30,
--     name = "John Doe"
-- }

-- Nested tables
local company = {
    name = "Tech Corp",
    employees = {
        {name = "Alice", role = "Developer"},
        {name = "Bob", role = "Designer"}
    },
    founded = 2020
}

print(dump(company))
-- Output:
-- {
--     employees = {
--         [1] = {
--             name = "Alice",
--             role = "Developer"
--         },
--         [2] = {
--             name = "Bob", 
--             role = "Designer"
--         }
--     },
--     founded = 2020,
--     name = "Tech Corp"
-- }
```

### Custom Formatting

```lua
local dump = require('dump')

-- Simple table
local person = {
    name = "John Doe",
    age = 30,
    active = true,
}

-- Custom indentation (2 spaces instead of 4)
print(dump(person, 2))
-- {
--   active = true,
--   age = 30,
--   name = "John Doe"
-- }

-- Adding padding at the beginning
print(dump(person, 4, 2))
--  {
--        active = true,
--        age = 30,
--        name = "John Doe"
--    }
```

### Using Filters

```lua
local dump = require('dump')

-- Filter sensitive information
local user = {
    username = "alice",
    password = "secret123",
    email = "alice@example.com"
}

local filtered = dump(user, nil, nil, function(val, depth, typ, use, key)
    if key == "password" then
        return "[HIDDEN]"
    end
    return val
end)

print(filtered)
-- {
--     email = "alice@example.com",
--     password = "[HIDDEN]",
--     username = "alice"
-- }

-- Transform values based on type
local data = {count = 0, rate = 0.75, items = {"a", "b"}}

local transformed = dump(data, nil, nil, function(val, depth, typ)
    if typ == "number" and val < 1 then
        return string.format("%.2f%%", val * 100)  -- Convert to percentage
    end
    return val
end)

print(transformed)
-- {
--     count = "0.00%",
--     items = {
--         [1] = "a",
--         [2] = "b"
--     },
--     rate = "75.00%"
-- }
```



## Edge Cases

### Circular References

The library automatically detects and handles circular references:

```lua
local dump = require('dump')

local t = {name = "parent"}
t.self = t  -- Circular reference

print(dump(t))
-- {
--     name = "parent",
--     self = <Circular table: 0x...>
-- }
```

### Special Keys

```lua
local dump = require('dump')

local special = {
    ["function"] = "reserved word",
    [123] = "numeric key", 
    [true] = "boolean key",
    ["key with spaces"] = "quoted key"
}

print(dump(special))
-- {
--     [123] = "numeric key",
--     [true] = "boolean key",
--     ["function"] = "reserved word",
--     ["key with spaces"] = "quoted key"
-- }
```

### Complex Data Types

```lua
local dump = require('dump')

local complex = {
    fn = function() return "hello" end,
    co = coroutine.create(function() end)
}

print(dump(complex))
-- {
--     co = "thread: 0x...",
--     fn = "function: 0x..."
-- }
```

## License

MIT License

