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

### str = dump( val [, indent [, padding [, filter [, udata [, reftrack ]]]]])

Converts a Lua value to its string representation.

**Parameters**

- `val:any`: The value to be converted to string
- `indent:integer`: Non-negative number of spaces for each indentation level (default: `4`)
- `padding:integer`: Non-negative additional indentation for table fields and closing braces (default: `0`)
- `filter:function`: Optional function to transform values during dumping (default: `nil`)
- `udata:any`: User data passed to the filter function (default: `nil`)
- `reftrack:boolean`: Annotate expanded tables and append a comment grouping circular references in values and keys (default: `false`)

**Returns**

- `string`: The string representation of the input value

**Filter Function**

```lua
val, nodump = filter(val, depth, typ, use, key, udata)
```

**Parameters**

- `val:any`: The current value being processed
- `depth:number`: `0` for a top-level non-table value; entries in the root table start at `1`
- `typ:string`: Type of the value (`"nil"`, `"boolean"`, `"number"`, `"string"`, `"table"`, `"function"`, `"userdata"`, `"thread"`)
- `use:string`: Context of usage - `"key"`, `"val"`, or `"circular"`
- `key:any`: `nil` for key filters, the transformed key for value filters, or the repeated table for circular-reference filters
- `udata:any`: User data passed from the main dump call

**Returns**

- `val:any`: The transformed value. Return `nil` when filtering a table entry's key or value to omit that entry.
- `nodump:boolean`: Control representation rather than omission (default: `false`). For non-circular table entries, `true` leaves string values unquoted and uses a quoted `tostring` result for table keys or values instead of expanding them.

`nodump` has no effect on top-level non-table values. Circular-reference string replacements are quoted, and table replacements are expanded unless `nodump` is `true`. Returning `nil` for a circular reference keeps its marker.

**Examples**

```lua
local dump = require('dump')
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
-- {
--       x = 1,
--       y = {
--           a = 2,
--           b = 3
--       }
--   }
```


## Quick Start

```lua
local dump = require('dump')

-- Basic usage
print(dump({name = "Alice", age = 25}))
-- Output:
-- {
--     age = 25,
--     name = "Alice"
-- }
```

## Usage Examples

### Basic Data Types

```lua
local dump = require('dump')

-- Primitive values
print(dump(nil))        --> nil
print(dump(true))       --> true
print(dump(42))         --> 42
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
-- {
--       active = true,
--       age = 30,
--       name = "John Doe"
--   }
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

Circular references are represented by quoted `<Circular ...>` markers containing the referenced table's `tostring()` result. Non-circular shared tables are expanded at each occurrence.

```lua
local dump = require('dump')

local t = {name = "parent"}
t.self = t  -- Circular reference

print(dump(t))
-- {
--     name = "parent",
--     self = "<Circular table: 0x...>"
-- }

-- Include a reference list
print(dump(t, 0, nil, nil, nil, true))
-- { --[[table: 0x...]] name = "parent", self = "<Circular table: 0x...>" }; --[[Circular References: -- In Values: $.self = "<Circular table: 0x...>" ]]
```

`reftrack = true` appends a diagnostic comment with `In Values` and `In Keys` sections, using `$` for the root. Each section is sorted as strings, and empty sections are omitted. Each expanded table, including empty tables and table keys, starts with a comment containing its `tostring()` result, so reference labels can be matched to their locations. Circular markers are unchanged; comments do not affect Lua readback. A table with no detected cycles produces an empty list. When loaded as Lua, circular markers remain strings.

Value references use `location = target`. Key references use `[{ "<key label>".field = target }] @ location`, where `location` identifies the table containing the key. Nested table keys appear inside nested `[{ ... }]` groups. In value paths, table keys use quoted typed identities, followed by the value table's identity in angle brackets, such as `$["table: 0xKEY"]<"table: 0xVALUE">.self`. The index identifies the key; the annotation identifies its associated value. This is diagnostic notation, not executable Lua.

Reference targets use the same quoted `<Circular ...>` markers as the dump body. Their identities can be matched to the table comments. Paths are not retained after expansion, so shared tables are tracked separately at each occurrence. Key-group labels use typed identities wrapped in angle brackets and quoted as a whole. Quotes and other special characters are escaped.

```lua
local dump = require('dump')

local key = {}
key.self = key
local root = { [key] = "value" }

print(dump(root, 0, nil, nil, nil, true))
-- { --[[table: 0x...]] [{ --[[table: 0x...]] self = "<Circular table: 0x...>" }] = "value" }; --[[Circular References: -- In Keys: [{ "<table: 0x...>".self = "<Circular table: 0x...>" }] @ $ ]]
```

Tracking identities follow `tostring()`, adding a `table: ` prefix unless it is already present. This applies to table identity comments and tracking labels; circular markers retain their original representation. Fallback labels follow `__tostring`; different keys returning the same string can have identical fallback labels. Cycle detection still uses table identity.

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

