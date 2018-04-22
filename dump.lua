--[[

  Copyright (C) 2018 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  dump.lua
  lua-dump
  Created by Masatoshi Teruya on 18/04/22.

--]]
--- file-scope variables
local type = type;
local floor = math.floor;
local tostring = tostring;
local tblsort = table.sort;
local tblconcat = table.concat;
local strmatch = string.match;
local strformat = string.format;
--- constants
local INFINITE_POS = math.huge;
local LUA_FIELDNAME_PAT = '^[a-zA-Z_][a-zA-Z0-9_]*$';
local FOR_KEY = 'key';
local FOR_VAL = 'val';
local FOR_CIRCULAR = 'circular';
local RESERVED_WORD = {
    -- primitive data
    ['nil']         = true,
    ['true']        = true,
    ['false']       = true,
    -- declaraton
    ['local']       = true,
    ['function']    = true,
    -- boolean logic
    ['and']         = true,
    ['or']          = true,
    ['not']         = true,
    -- conditional statement
    ['if']          = true,
    ['elseif']      = true,
    ['else']        = true,
    -- iteration statement
    ['for']         = true,
    ['in']          = true,
    ['while']       = true,
    ['until']       = true,
    ['repeat']      = true,
    -- jump statement
    ['break']       = true,
    ['goto']        = true,
    ['return']      = true,
    -- block scope statement
    ['then']        = true,
    ['do']          = true,
    ['end']         = true
};
local DEFAULT_INDENT = 4;


--- filter function for dump
-- @param val
-- @param typ
-- @param asa
-- @paran key
-- @param udata
-- @return val
-- @return skip
local function DEFAULT_FILTER( val )
    return val;
end


--- sortIndex
-- @param a
-- @param b
local function sortIndex( a, b )
    if a.typ == b.typ then
        if a.typ == 'boolean' then
            return b.key;
        end

        return a.key < b.key;
    end

    return a.typ == 'number';
end


--- dumptbl
-- @param tbl
-- @param indent
-- @param nestIndent
-- @param ctx
-- @return str
local function dumptbl( tbl, indent, nestIndent, ctx )
    local ref = tostring( tbl );

    -- circular reference
    if ctx.circular[ref] then
        local val = ctx.filter(
            tbl, type( tbl ), FOR_CIRCULAR, tbl, ctx.udata
        );

        if val ~= nil and val ~= tbl then
            local t = type( val );

            if t == 'string' then
                return strformat( '%q', val );
            elseif t == 'number' or t == 'boolean' then
                return tostring( val );
            end

            return strformat( '%q', tostring( val ) );
        end

        return '"<Circular ' .. ref .. '>"';
    else
        local res = {};
        local arr = {};
        local narr = 0;
        local fieldIndent = indent .. nestIndent;
        local arrFmt = fieldIndent .. '[%s] = %s';
        local strFmt = fieldIndent .. '%s = %s';
        local ptrFmt = fieldIndent .. '[%q] = %s';

        -- save reference
        ctx.circular[ref] = true;

        for k, v in pairs( tbl ) do
            -- check key
            k = ctx.filter( k, type( k ), FOR_KEY, nil, ctx.udata );
            if k then
                local tk = type( k );
                -- check value
                local val, skip = ctx.filter( v, type( v ), FOR_VAL, k,
                                              ctx.udata );

                -- just convert to string
                if skip then
                    v = tostring( val );
                else
                    local tv = type( val );

                    if tv == 'table' then
                        v = dumptbl( val, fieldIndent, nestIndent, ctx );
                    elseif tv == 'string' then
                        v = strformat( '%q', val );
                    elseif tv == 'number' or tv == 'boolean' then
                        v = tostring( val );
                    else
                        v = strformat( '%q', tostring( val ) );
                    end
                end

                if tk == 'number' or tk == 'boolean' then
                    v = strformat( arrFmt, tostring( k ), v );
                elseif tk == 'string' and not RESERVED_WORD[k] and
                       strmatch( k, LUA_FIELDNAME_PAT ) then
                    v = strformat( strFmt, k, v );
                else
                    k = tostring( k );
                    v = strformat( ptrFmt, k, v );
                    tk = 'string';
                end

                -- add to array
                narr = narr + 1;
                arr[narr] = {
                    typ = tk,
                    key = k,
                    val = v
                };
            end
        end

        -- remove reference
        ctx.circular[ref] = nil;
        -- concat result
        if narr > 0 then
            tblsort( arr, sortIndex );

            for i = 1, narr do
                res[i] = arr[i].val;
            end
            res[1] = '{' .. ctx.LF .. res[1];
            res = tblconcat( res, ',' .. ctx.LF ) .. ctx.LF .. indent .. '}';
        else
            res = '{}';
        end

        return res;
    end

end


--- isuint
-- @param v
-- @return ok
local function isUInt( v )
    return type( v ) == 'number' and v < INFINITE_POS and v >= 0 and
           floor( v ) == v;
end


--- dump
-- @param val
-- @param indent
-- @param padding
-- @param filter
-- @param udata
-- @return str
local function dump( val, indent, padding, filter, udata )
    local t = type( val );

    -- check indent
    if indent == nil then
        indent = DEFAULT_INDENT;
    elseif not isUInt( indent ) then
        error( 'indent must be unsigned integer' );
    end

    -- check padding
    if padding == nil then
        padding = 0;
    elseif not isUInt( padding ) then
        error( 'padding must be unsigned integer' );
    end

    -- check filter
    if filter == nil then
        filter = DEFAULT_FILTER;
    elseif type( filter ) ~= 'function' then
        error( 'opt.filter must be function' );
    end

    -- dump table
    if t == 'table' then
        indent = strformat( '%' .. tostring( indent ) .. 's', '' );
        padding = strformat( '%' .. tostring( padding ) .. 's', '' );
        return dumptbl( val, padding, indent, {
            LF = indent == '' and ' ' or '\n',
            circular = {},
            filter = filter,
            udata = udata
        });
    end

    val = filter( val, t, FOR_VAL, nil, udata );
    return tostring( val );
end


return dump;
