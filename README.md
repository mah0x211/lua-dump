lua-dump
=========

[![test](https://github.com/mah0x211/lua-dump/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-dump/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-dump/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-dump)

convert lua data to string.

---

## Installation

```sh
luarocks install dump
```


## str = dump( val [, indent [, padding [, filter [, udata]]]] )

returns the stringified value.

**Parameters**

- `val:any`: any data.
- `indent:uint`: insert indent into the output for readability purposes.
- `padding:uint`: insert whitespace to head of output for readability purposes.
- `filter:function`: filter function
- `udata:any`: pass to last argument of filter function.

**Returns**

- `str:string`: the stringified value


**Fitler Function**

### val, nodump = filter( val, depth, typ, use, key, udata )

**Parameters**

- `val:any`: any data.
- `depth:uint`: depth of nesting.
- `typ:string`: type of val.
- `use:string`: use for; `'key'`, `'val'` or `'circular'`.
- `key`: key data of val.
- `udata:any`: pass to last argument of filter function.

**Returns**

- `val:any`: filtered value.
- `nodump:boolean`: no dump a return value if `true` (default: `false`)

