--
-- Copyright (C) 2018 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- dump.lua
-- lua-dump
-- Created by Masatoshi Teruya on 18/04/22.
--
--- file-scope variables
local type = type
local floor = math.floor
local tostring = tostring
local tblsort = table.sort
local tblconcat = table.concat
local strmatch = string.match
local strformat = string.format
local strrep = string.rep
--- constants
local INFINITE_POS = math.huge
local LUA_FIELDNAME_PAT = '^[a-zA-Z_][a-zA-Z0-9_]*$'
local FOR_KEY = 'key'
local FOR_VAL = 'val'
local FOR_CIRCULAR = 'circular'
local RESERVED_WORD = {
    -- primitive data
    ['nil'] = true,
    ['true'] = true,
    ['false'] = true,
    -- declaraton
    ['local'] = true,
    ['function'] = true,
    -- boolean logic
    ['and'] = true,
    ['or'] = true,
    ['not'] = true,
    -- conditional statement
    ['if'] = true,
    ['elseif'] = true,
    ['else'] = true,
    -- iteration statement
    ['for'] = true,
    ['in'] = true,
    ['while'] = true,
    ['until'] = true,
    ['repeat'] = true,
    -- jump statement
    ['break'] = true,
    ['goto'] = true,
    ['return'] = true,
    -- block scope statement
    ['then'] = true,
    ['do'] = true,
    ['end'] = true,
}
local DEFAULT_INDENT = 4

--- @alias dump.filter fun(val: any, depth: integer, vtype: string, use: string, key: any, udata: any): (any, boolean?)

--- @class dump.ctx
--- @field LF string line feed character
--- @field indent string indentation string
--- @field padding string padding string
--- @field depth integer current depth of the table
--- @field circular table a table that holds circular references
--- @field filter dump.filter filter function
--- @field udata any user data that is passed to the filter function

--- @class dump.table
--- @field typ string type of the value
--- @field key string the key of the value
--- @field val string the dumped key-value pair as a string

--- dump a table to a string array
--- @param ctx table
--- @param tbl table
--- @param dump_next_table fun(ctx: table, tbl: table):string
--- @return dump.table[] arr the dumped strings
--- @return integer narr the number of dumped strings
local function dump_table(ctx, tbl, dump_next_table)
    local arr = {}
    local narr = 0
    for k, v in pairs(tbl) do
        -- check key
        local key, nokdump = ctx.filter(k, ctx.depth, type(k), FOR_KEY, nil,
                                        ctx.udata)

        if key ~= nil then
            -- check val
            local val, novdump = ctx.filter(v, ctx.depth, type(v), FOR_VAL, key,
                                            ctx.udata)
            local kv

            if val ~= nil then
                local kt = type(key)
                local vt = type(val)

                -- convert key to suitable to be safely read back
                -- by the Lua interpreter
                if kt == 'number' or kt == 'boolean' then
                    k = key
                    key = '[' .. tostring(key) .. ']'
                elseif kt == 'table' and not nokdump then
                    -- dump table value
                    key = '[' .. dump_next_table(ctx, key) .. ']'
                    k = key
                    kt = 'string'
                elseif kt ~= 'string' or RESERVED_WORD[key] or
                    not strmatch(key, LUA_FIELDNAME_PAT) then
                    key = strformat("[%q]", tostring(key), v)
                    k = key
                    kt = 'string'
                end

                -- convert key-val pair to suitable to be safely read back
                -- by the Lua interpreter
                if vt == 'number' or vt == 'boolean' then
                    val = tostring(val)
                elseif vt == 'string' then
                    -- dump a string-value
                    if not novdump then
                        val = strformat('%q', val)
                    end
                elseif vt == 'table' and not novdump then
                    val = dump_next_table(ctx, val)
                else
                    val = strformat('%q', tostring(val))
                end
                kv = strformat('%s%s = %s', ctx.indent, key, val)

                -- add to array
                narr = narr + 1
                arr[narr] = {
                    typ = kt,
                    key = k,
                    val = kv,
                }
            end
        end
    end

    return arr, narr
end

--- dump a circular referenced table to a string
--- @param ctx dump.ctx
--- @param tbl table the table to be dumped
--- @param dump_next_table fun(ctx: dump.ctx, tbl: table):string
--- @return string str the dumped string or nil if the table is not circular
local function dump_circular(ctx, tbl, ref, dump_next_table)
    local val, nodump = ctx.filter(tbl, ctx.depth, type(tbl), FOR_CIRCULAR, tbl,
                                   ctx.udata)
    if val ~= nil and val ~= tbl then
        local t = type(val)

        if t == 'number' or t == 'boolean' then
            return tostring(val)
        elseif t == 'table' and not nodump then
            -- dump table value
            return dump_next_table(ctx, val)
        end
        -- otherwise, convert to quoted string
        return strformat('%q', tostring(val))
    end

    return '"<Circular ' .. ref .. '>"'
end

--- sort_index
--- @param a table
--- @param b table
local function sort_index(a, b)
    if a.typ == b.typ then
        if a.typ == 'boolean' then
            -- false < true
            return not a.key and b.key
        end
        -- number, string or other types
        return a.key < b.key
    end

    -- 1st priority is number
    if a.typ == 'number' then
        return true
    elseif b.typ == 'number' then
        return false
    end

    -- 2nd priority is boolean
    return a.typ == 'boolean'
end

--- dump a table by calling dump_table.
--- This function is used to handle the initial call with depth 1.
--- @param ctx table
--- @param tbl table
--- @return string
local function dump_next_table(ctx, tbl)
    -- update context
    local depth = ctx.depth or 0
    ctx.depth = depth + 1

    local ref = tostring(tbl)
    if ctx.circular[ref] then
        -- dump circular referenced table to a string
        -- if it is circular, it will return a string that indicates the circular references
        local str = dump_circular(ctx, tbl, ref, dump_next_table)
        -- restore context
        ctx.depth = depth
        return str
    end

    local indent = ctx.indent
    ctx.indent = indent .. ctx.padding

    -- save reference
    ctx.circular[ref] = true
    -- dump table
    local arr, narr = dump_table(ctx, tbl, dump_next_table)
    -- remove reference
    ctx.circular[ref] = nil
    -- restore context
    ctx.indent = indent
    ctx.depth = depth

    if narr == 0 then
        -- empty table
        return '{}'
    end

    -- concat result array to a string
    tblsort(arr, sort_index)
    local res = {}
    for i = 1, narr do
        res[i] = arr[i].val
    end
    res[1] = '{' .. ctx.LF .. res[1]
    return tblconcat(res, ',' .. ctx.LF) .. ctx.LF .. ctx.indent .. '}'
end

--- determine if the value is an unsigned integer
--- @param v any
--- @return boolean ok true if the value is an unsigned integer
local function is_uint(v)
    return type(v) == 'number' and v < INFINITE_POS and v >= 0 and floor(v) == v
end

--- filter function that is called for each values.
--- It can be used to filter out values that should not be dumped.
--- If the function returns nodump as true, the value will not be dumped.
--- If the function returns a value that is not nil, it will be used as the dumped value.
--- @param val any
--- @param depth integer depth of the value in the table
--- @param vtype string type of the value
--- @param use string one of FOR_KEY, FOR_VAL, FOR_CIRCULAR
--- @param key any key of the value if use is FOR_VAL or FOR_CIRCULAR
--- @param udata any user data that is passed from the dump function
--- @return any val the value to be dumped or nil to skip dumping
--- @return boolean? nodump if true, the value will not be dumped
local function DEFAULT_FILTER(val, depth, vtype, use, key, udata)
    return val
end

--- dump a value to a string that can be safely read back by the Lua interpreter.
--- @param val any the value to be dumped
--- @param indent integer? the number of spaces to indent each line (default: 4).
--- @param padding integer? the number of spaces to padding each line (default: 0).
--- @param filter dump.filter filter function that is called for each values
--- @param udata any user data that is passed to the filter function
--- @return string str the dumped string
local function dump(val, indent, padding, filter, udata)
    local t = type(val)

    -- check indent
    if indent == nil then
        indent = DEFAULT_INDENT
    elseif not is_uint(indent) then
        error('indent must be unsigned integer', 2)
    end

    -- check padding
    if padding == nil then
        padding = 0
    elseif not is_uint(padding) then
        error('padding must be unsigned integer', 2)
    end

    -- check filter
    if filter == nil then
        filter = DEFAULT_FILTER
    elseif type(filter) ~= 'function' then
        error('filter must be function', 2)
    end

    -- dump table
    if t == 'table' then
        local ispace = strrep(' ', indent)
        return dump_next_table({
            LF = ispace == '' and ' ' or '\n',
            indent = strrep(' ', padding),
            padding = ispace,
            depth = 0,
            circular = {},
            filter = filter,
            udata = udata,
        }, val)
    end

    -- dump value
    local v = filter(val, 0, t, FOR_VAL, nil, udata)
    t = type(v)
    v = tostring(v)
    if t == 'number' or t == 'boolean' or t == 'nil' then
        return v
    end
    -- non number/boolean/nil values are converted to quoted string
    return strformat('%q', v)
end

return dump
