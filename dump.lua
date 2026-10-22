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
local strsub = string.sub
local strfind = string.find
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
    ['global'] = true,
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
--- @field circular table currently expanded tables used for cycle detection
--- @field filter dump.filter filter function
--- @field udata any user data that is passed to the filter function
--- @field reftrack boolean whether to append a circular-reference list comment
--- @field refs table circular-reference rows grouped by values and keys

--- @class dump.table
--- @field typ string type of the value
--- @field key number|boolean|string the key used for sorting
--- @field val string the dumped key-value pair as a string
--- @field sortval string? key-subtree entry without identity comments

--- Add the value type unless its tostring representation already includes it.
--- @param v any
--- @param str string? an existing tostring result to reuse
--- @return string
local function to_typed_string(v, str)
    local prefix = type(v) .. ': '
    str = str or tostring(v)
    if strsub(str, 1, #prefix) == prefix then
        return str
    end
    return prefix .. str
end

--- Wrap text in a Lua long comment without allowing an early closing delimiter.
--- @param text string
--- @return string
local function long_comment(text)
    local eq = ''
    while strfind(text, ']' .. eq .. ']', 1, true) do
        eq = eq .. '='
    end
    return '--[' .. eq .. '[' .. text .. ']' .. eq .. ']'
end

--- Append a field to a value path or to deferred key-path segments.
--- Value paths are strings; key paths retain their parent and tostring label.
--- @param pathname string|table the current pathname
--- @param key string the formatted key to be appended
--- @param keylabel string? the typed tostring label for a table key
--- @return string|table pathname the updated pathname
local function append2pathname(pathname, key, keylabel)
    local field = keylabel and strformat('[%q]', keylabel) or
                      (strsub(key, 1, 1) == '[' and key or '.' .. key)
    if type(pathname) == 'string' then
        return pathname .. field
    end
    return {
        parent = pathname,
        field = field,
    }
end

--- Annotate the table value at a location using its existing tostring result.
--- @param pathname string|table
--- @param tbl table
--- @param ref string
--- @return string|table
local function append_table_identity(pathname, tbl, ref)
    local identity = '<' .. strformat('%q', to_typed_string(tbl, ref)) .. '>'
    if type(pathname) == 'string' then
        return pathname .. identity
    end
    return {
        parent = pathname,
        field = identity,
    }
end

--- Render a key location without confusing it with the associated value.
--- @param pathname string|table
--- @param suffix string
--- @return string
local function format_reference_path(pathname, suffix)
    while type(pathname) == 'table' do
        if pathname.label then
            local label = pathname.label
            suffix = '[{ ' .. strformat('%q', '<' .. label .. '>') .. suffix ..
                         ' }]'
            if type(pathname.parent) == 'string' then
                return suffix .. ' @ ' .. pathname.parent
            end
        else
            suffix = pathname.field .. suffix
        end
        pathname = pathname.parent
    end
    return pathname .. suffix
end

--- dump a table to a string array
--- @param ctx dump.ctx
--- @param pathname string|table
--- @param tbl table
--- @param dump_next_table fun(ctx: dump.ctx, pathname: string|table, tbl: table, annotate: boolean?): (string, string?)
--- @return dump.table[] arr the dumped strings
--- @return integer narr the number of dumped strings
local function dump_table(ctx, pathname, tbl, dump_next_table)
    local arr = {}
    local narr = 0
    local sorting = type(pathname) == 'table'
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
                local sortkey = key
                local kt = type(key)
                local vt = type(val)
                local keylabel = ctx.reftrack and kt == 'table' and
                                     to_typed_string(key)
                local plainkey, plainval

                -- convert key to suitable to be safely read back
                -- by the Lua interpreter
                if kt == 'number' or kt == 'boolean' then
                    sortkey = key
                    key = '[' .. tostring(key) .. ']'
                elseif kt == 'table' and not nokdump then
                    -- A table key has its own location within the parent dump.
                    local keypath = pathname
                    if ctx.reftrack then
                        keypath = {
                            parent = pathname,
                            label = keylabel,
                        }
                    end
                    local rendered
                    rendered, plainkey = dump_next_table(ctx, keypath, key)
                    key = '[' .. rendered .. ']'
                    sortkey = '[' .. (plainkey or rendered) .. ']'
                    plainkey = sortkey
                    kt = 'string'
                elseif kt ~= 'string' or RESERVED_WORD[key] or
                    not strmatch(key, LUA_FIELDNAME_PAT) then
                    key = strformat("[%q]", tostring(key), v)
                    sortkey = key
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
                    val, plainval = dump_next_table(ctx, ctx.reftrack and
                                                        append2pathname(
                                                            pathname, key,
                                                            keylabel) or
                                                        pathname, val,
                                                    not not keylabel)
                else
                    val = strformat('%q', tostring(val))
                end
                kv = strformat('%s%s = %s', ctx.indent, key, val)

                -- add to array
                narr = narr + 1
                arr[narr] = {
                    typ = kt,
                    key = sortkey,
                    val = kv,
                    sortval = sorting and
                        strformat('%s%s = %s', ctx.indent, plainkey or key,
                                  plainval or val) or nil,
                }
            end
        end
    end

    return arr, narr
end

--- dump a circular referenced table to a string
--- @param ctx dump.ctx
--- @param pathname string|table the pathname of the table
--- @param tbl table the table to be dumped
--- @param ref string the table's tostring representation
--- @param dump_next_table fun(ctx: dump.ctx, pathname: string|table, tbl: table, annotate: boolean?): (string, string?)
--- @param annotate boolean? whether to annotate the final table value
--- @return string str the representation of the circular table
--- @return string? sortstr rendering without identity comments for a table-key subtree
local function dump_circular(ctx, pathname, tbl, ref, dump_next_table, annotate)
    local val, nodump = ctx.filter(tbl, ctx.depth, type(tbl), FOR_CIRCULAR, tbl,
                                   ctx.udata)
    if val ~= nil and val ~= tbl then
        local t = type(val)

        if t == 'number' or t == 'boolean' then
            return tostring(val)
        elseif t == 'table' and not nodump then
            -- dump table value
            return dump_next_table(ctx, pathname, val, annotate)
        end
        -- otherwise, convert to quoted string
        return strformat('%q', tostring(val))
    end

    local marker = strformat('%q', '<Circular ' .. ref .. '>')
    if ctx.reftrack then
        if annotate then
            pathname = append_table_identity(pathname, tbl, ref)
        end
        local rows = type(pathname) == 'string' and ctx.refs.values or
                         ctx.refs.keys
        rows[#rows + 1] = format_reference_path(pathname, ' = ' .. marker)
    end
    return marker
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
--- @param ctx dump.ctx
--- @param pathname string|table the path to the current table
--- @param tbl table
--- @param annotate boolean? whether to annotate the final table value
--- @return string
--- @return string? sortstr rendering without identity comments for a table-key subtree
local function dump_next_table(ctx, pathname, tbl, annotate)
    -- update context
    local depth = ctx.depth or 0
    ctx.depth = depth + 1

    local ref = tostring(tbl)
    if ctx.circular[tbl] then
        -- dump circular referenced table to a string
        -- if it is circular, it will return a string that indicates the circular references
        local str, sortstr = dump_circular(ctx, pathname, tbl, ref,
                                           dump_next_table, annotate)
        -- restore context
        ctx.depth = depth
        return str, sortstr
    end

    if ctx.reftrack and annotate then
        pathname = append_table_identity(pathname, tbl, ref)
    end
    local indent = ctx.indent
    ctx.indent = indent .. ctx.padding

    -- Track table identity only while the table is an active ancestor.
    ctx.circular[tbl] = true
    -- dump table
    local arr, narr = dump_table(ctx, pathname, tbl, dump_next_table)
    -- remove reference
    ctx.circular[tbl] = nil
    -- restore context
    ctx.indent = indent
    ctx.depth = depth

    local opening = '{'
    if ctx.reftrack then
        opening = opening .. ' ' .. long_comment(to_typed_string(tbl, ref))
    end
    if narr == 0 then
        -- empty table
        return opening .. '}', '{}'
    end

    -- concat result array to a string
    tblsort(arr, sort_index)
    local res = {}
    local sortres = type(pathname) == 'table' and {}
    for i = 1, narr do
        res[i] = arr[i].val
        if sortres then
            sortres[i] = arr[i].sortval
        end
    end
    local sortstr
    if sortres then
        -- A table key is compared by content, without diagnostic annotations.
        sortres[1] = '{' .. ctx.LF .. sortres[1]
        sortstr = tblconcat(sortres, ',' .. ctx.LF) .. ctx.LF .. ctx.indent ..
                      '}'
    end
    res[1] = opening .. ctx.LF .. res[1]
    return tblconcat(res, ',' .. ctx.LF) .. ctx.LF .. ctx.indent .. '}', sortstr
end

--- determine if the value is an unsigned integer
--- @param v any
--- @return boolean ok true if the value is an unsigned integer
local function is_uint(v)
    return type(v) == 'number' and v < INFINITE_POS and v >= 0 and floor(v) == v
end

--- Filter keys, values, and circular references.
--- Returning nil for a table entry's key or value omits that entry.
--- nodump controls representation; it does not omit entries.
--- @param val any
--- @param depth integer depth of the value in the table
--- @param vtype string type of the value
--- @param use string one of FOR_KEY, FOR_VAL, FOR_CIRCULAR
--- @param key any key of the value if use is FOR_VAL or FOR_CIRCULAR
--- @param udata any user data that is passed from the dump function
--- @return any val the transformed value; nil omits table entries for key/value filters
--- @return boolean? nodump controls string quoting and table expansion
local function DEFAULT_FILTER(val, depth, vtype, use, key, udata)
    return val
end

--- dump a value to a string that can be safely read back by the Lua interpreter.
--- @param val any the value to be dumped
--- @param indent integer? the number of spaces to indent each line (default: 4).
--- @param padding integer? the number of spaces to padding each line (default: 0).
--- @param filter dump.filter filter function that is called for each values
--- @param udata any user data that is passed to the filter function
--- @param reftrack boolean? append a circular-reference list comment (default: false)
--- @return string str the dumped string
local function dump(val, indent, padding, filter, udata, reftrack)
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

    -- check reftrack
    if reftrack ~= nil and type(reftrack) ~= 'boolean' then
        error('reftrack must be boolean', 2)
    end

    -- dump table
    if t == 'table' then
        local ispace = strrep(' ', indent)
        local LF = ispace == '' and ' ' or '\n'
        local refs = reftrack and {
            values = {},
            keys = {},
        }
        local str = dump_next_table({
            LF = LF,
            indent = strrep(' ', padding),
            padding = ispace,
            depth = 0,
            circular = {},
            filter = filter,
            udata = udata,
            reftrack = reftrack == true,
            refs = refs,
        }, '$', val)
        if reftrack then
            local values, keys = refs.values, refs.keys
            local delim = ispace == '' and '; ' or LF
            local sections = {}
            tblsort(values)
            tblsort(keys)
            if #values > 0 then
                sections[#sections + 1] =
                    '-- In Values:' .. LF .. tblconcat(values, delim)
            end
            if #keys > 0 then
                sections[#sections + 1] =
                    '-- In Keys:' .. LF .. tblconcat(keys, delim)
            end
            local comment = 'Circular References:' .. LF ..
                                tblconcat(sections, LF .. LF) .. LF
            str = str .. delim .. long_comment(comment)
        end
        return str
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
