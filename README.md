lua-dump
=========

stringified lua data structures, suitable for both printing and loading as chunk.

---

## Installation

```sh
luarocks install dump --from=http://mah0x211.github.io/rocks/
```


## Functions

### str = dump( val [, indent [, padding [, filter [, udata]]]] )

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

### val, nodump = filter( val, depth, typ, use, key, udata )

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

