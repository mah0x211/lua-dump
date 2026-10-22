require('luacov')
local builtin_assert = assert

-- Helper function to check if string contains substring
local function contains(str, substr)
    return string.find(str, substr, 1, true) ~= nil
end

local assert = setmetatable({}, {
    __call = function(_, ...)
        builtin_assert(...)
    end,
    __index = {
        equal = function(a, b)
            if a ~= b then
                error(('Expected %s, got %s'):format(tostring(b), tostring(a)),
                      2)
            end
        end,
        not_equal = function(a, b)
            if a == b then
                error(('Expected not %s'):format(tostring(b)), 2)
            end
        end,
        throws = function(func)
            local status, err = pcall(func)
            if status then
                error('Expected function to throw an error, but it did not', 2)
            end
            return err
        end,
        contains = function(str, substr)
            if not contains(str, substr) then
                error(
                    ('Expected string to contain "%s", but it did not. String: %s'):format(
                        substr, str), 2)
            end
        end,
        not_contains = function(str, substr)
            if contains(str, substr) then
                error(
                    ('Expected string not to contain "%s", but it did. String: %s'):format(
                        substr, str), 2)
            end
        end,
    },
})
local alltests = {}
local testcase = setmetatable({}, {
    __newindex = function(_, k, v)
        assert(not alltests[k], 'duplicate test name: ' .. k)
        alltests[k] = true
        alltests[#alltests + 1] = {
            name = k,
            func = v,
        }
    end,
})

local function run_all_tests()
    local gettime = os.time
    local stdout = io.stdout
    local elapsed = gettime()
    local errs = {}
    print(('Running %d tests...\n'):format(#alltests))
    for _, test in ipairs(alltests) do
        stdout:write('- ', test.name, ' ... ')
        local t = gettime()
        local ok, err = pcall(test.func)
        t = gettime() - t
        if ok then
            stdout:write('ok')
        else
            stdout:write('failed')
            errs[#errs + 1] = {
                name = test.name,
                err = err,
            }
        end
        stdout:write(' (', ('%.2f'):format(t), ' sec)\n')
    end
    elapsed = gettime() - elapsed
    print('')
    if #errs == 0 then
        print(('%d tests passed. (%.2f sec)\n'):format(#alltests, elapsed))
        os.exit(0)
    end

    print(('Failed %d tests:\n'):format(#errs))
    local stderr = io.stderr
    for _, err in ipairs(errs) do
        stderr:write('- ', err.name)
        stderr:write(err.err, '\n')
    end
    print('')
    os.exit(-1)
end

-- Describe the test cases
local dump = require('dump')

-- Expected comment decoration; individual tests specify the reference rows.
local function tracking_comment(values, keys, compact)
    local LF = compact and ' ' or '\n'
    local sep = compact and '; ' or '\n'
    local sections = {}
    if #values > 0 then
        sections[#sections + 1] = '-- In Values:' .. LF .. table.concat(values, sep)
    end
    if #keys > 0 then
        sections[#sections + 1] = '-- In Keys:' .. LF .. table.concat(keys, sep)
    end
    local text = 'Circular References:' .. LF ..
                     table.concat(sections, LF .. LF) .. LF
    local eq = ''
    while text:find(']' .. eq .. ']', 1, true) do
        eq = eq .. '='
    end
    return (compact and '; ' or '\n') .. '--[' .. eq .. '[' .. text .. ']' .. eq .. ']'
end

-- Check the reference-list suffix and read back the original output unchanged.
local function assert_tracking(result, values, keys, compact)
    local expected = tracking_comment(values, keys, compact)
    assert.equal(result:sub(-#expected), expected)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    return chunk()
end

function testcase.dump_non_table_value()
    -- test that non-table values are dumped correctly

    -- Test basic value types
    assert.equal(dump(nil), 'nil')
    assert.equal(dump(true), 'true')
    assert.equal(dump(false), 'false')
    assert.equal(dump(123), '123')
    assert.equal(dump(123.45), '123.45')
    assert.equal(dump(-123.45), '-123.45')
    assert.equal(dump("hello"), '"hello"')

    -- Test with custom filter
    local result = dump("test", nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if vtype == "string" then
            return val, true -- nodump = true
        end
        return val
    end)
    assert.equal(result, '"test"')
end

function testcase.dump_unnested_table()
    -- test that un-nested tables are dumped correctly

    -- Empty table
    assert.equal(dump({}), '{}')

    -- Simple table with number keys
    local result = dump({
        1,
        2,
        3,
    })
    assert.equal(result, [[{
    [1] = 1,
    [2] = 2,
    [3] = 3
}]])

    -- Simple table with string keys
    local result2 = dump({
        a = 1,
        b = 2,
    })
    assert.equal(result2, [[{
    a = 1,
    b = 2
}]])

    -- Mixed keys
    local result3 = dump({
        [1] = "one",
        [2] = "two",
        [3] = "three",
        ["foo"] = "foo-value",
        ["bar"] = "bar-value",
        [true] = "true-bool",
        [false] = "false-bool",
    })
    assert.equal(result3, [[{
    [1] = "one",
    [2] = "two",
    [3] = "three",
    [false] = "false-bool",
    [true] = "true-bool",
    bar = "bar-value",
    foo = "foo-value"
}]])
end

function testcase.dump_nested_table()
    -- test nested tables
    local nested = {
        level1 = {
            level2 = {
                value = "deep",
            },
        },
    }
    local result = dump(nested)
    assert.equal(result, [[{
    level1 = {
        level2 = {
            value = "deep"
        }
    }
}]])
end

function testcase.dump_circular_reference()
    -- test circular reference handling
    local t1 = {}
    local t2 = {
        ref = t1,
    }
    t1.back = t2

    local result = dump(t1)
    -- Construct expected string using actual table address
    local expected = string.format([[{
    back = {
        ref = "<Circular %s>"
    }
}]], tostring(t1))
    assert.equal(result, expected)
end

function testcase.dump_circular_reference_with_filter()
    -- test circular reference with custom filter
    local t1 = {}
    t1.self = t1

    -- Filter that returns different value for circular reference
    local result = dump(t1, nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return "CIRCULAR_REF"
        end
        return val
    end)
    assert.equal(result, [[{
    self = "CIRCULAR_REF"
}]])

    -- Filter that returns table for circular reference (should trigger recursive dump)
    local filter_table = {
        replacement = "value",
    }
    local result2 = dump(t1, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return filter_table
        end
        return val
    end)
    assert.equal(result2, [[{
    self = {
        replacement = "value"
    }
}]])

    -- Filter that returns nodump=true for circular reference
    local dyntbl
    local result3 = dump(t1, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            dyntbl = {
                nodump = true,
            }
            return tostring(dyntbl), true
        end
        return val
    end)
    -- The result contains a dynamic table address
    assert.equal(result3, ([[{
    self = %q
}]]):format(tostring(dyntbl)))
end

function testcase.dump_special_keys()
    -- test special key handling

    -- Reserved words as keys
    local t = {
        ['if'] = 'keyword',
        ['local'] = 'reserved',
        ['function'] = 'builtin',
    }
    local result = dump(t)
    assert.equal(result, [[{
    ["function"] = "builtin",
    ["if"] = "keyword",
    ["local"] = "reserved"
}]])

    -- Invalid field names
    local t2 = {
        ['123invalid'] = 'number_start',
        ['key-with-dash'] = 'dash',
    }
    local result2 = dump(t2)
    assert.equal(result2, [[{
    ["123invalid"] = "number_start",
    ["key-with-dash"] = "dash"
}]])

    -- Table as key
    local key_table = {
        nested = "key",
    }
    local t3 = {
        [key_table] = "table_key",
    }
    local result3 = dump(t3)
    assert.equal(result3, [[{
    [{
        nested = "key"
    }] = "table_key"
}]])
end

function testcase.dump_indent_and_padding()
    -- test indent and padding options

    local t = {
        a = 1,
        b = 2,
    }

    -- Test with indent = 0 (single line)
    local result1 = dump(t, 0)
    assert.not_contains(result1, '\n')

    -- Test with custom indent
    local result2 = dump(t, 2)
    assert.equal(result2, [[{
  a = 1,
  b = 2
}]])

    -- Test with padding
    local result3 = dump(t, 4, 2)
    -- The result should be properly padded and indented
    assert.equal(result3, [[{
      a = 1,
      b = 2
  }]])
end

function testcase.dump_filter_functionality()
    -- test comprehensive filter functionality

    local t = {
        keep = "this",
        remove = "that",
        number = 42,
        nested = {
            inner = "value",
        },
    }

    -- Filter that removes certain keys
    local result1 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'key' and val == 'remove' then
            return nil -- skip this key-value pair
        end
        return val
    end)
    assert.equal(result1, [[{
    keep = "this",
    nested = {
        inner = "value"
    },
    number = 42
}]])

    -- Filter that modifies values
    local result2 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'val' and key == 'number' then
            return val * 2
        end
        return val
    end)
    assert.equal(result2, [[{
    keep = "this",
    nested = {
        inner = "value"
    },
    number = 84,
    remove = "that"
}]])

    -- Filter with user data
    local userdata = {
        prefix = "TEST_",
    }
    local result3 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'val' and vtype == 'string' then
            return udata.prefix .. val
        end
        return val
    end, userdata)
    assert.equal(result3, [[{
    keep = "TEST_this",
    nested = {
        inner = "TEST_value"
    },
    number = 42,
    remove = "TEST_that"
}]])
end

function testcase.dump_error_cases()
    -- test error conditions

    -- Invalid indent
    assert.throws(function()
        dump({}, -1)
    end)

    assert.throws(function()
        dump({}, 1.5)
    end)

    assert.throws(function()
        dump({}, "invalid")
    end)

    -- Invalid padding
    assert.throws(function()
        dump({}, nil, -1)
    end)

    assert.throws(function()
        dump({}, nil, 1.5)
    end)

    assert.throws(function()
        dump({}, nil, "invalid")
    end)

    -- Invalid filter
    assert.throws(function()
        dump({}, nil, nil, "not_a_function")
    end)
end

function testcase.dump_complex_structures()
    -- test complex data structures

    local complex = {
        array = {
            1,
            2,
            3,
            4,
            5,
        },
        hash = {
            name = "test",
            value = 123,
            flag = true,
        },
        mixed = {
            [1] = "first",
            [2] = "second",
            key = "value",
            [false] = "false_key",
            [42] = "number_key",
        },
        deep = {
            level1 = {
                level2 = {
                    level3 = {
                        final = "deep_value",
                    },
                },
            },
        },
    }

    local result = dump(complex)

    -- Verify the complete structure matches exactly
    assert.equal(result, [[{
    array = {
        [1] = 1,
        [2] = 2,
        [3] = 3,
        [4] = 4,
        [5] = 5
    },
    deep = {
        level1 = {
            level2 = {
                level3 = {
                    final = "deep_value"
                }
            }
        }
    },
    hash = {
        flag = true,
        name = "test",
        value = 123
    },
    mixed = {
        [1] = "first",
        [2] = "second",
        [42] = "number_key",
        [false] = "false_key",
        key = "value"
    }
}]])
end

function testcase.dump_string_handling()
    -- test string value handling with filter

    local t = {
        normal = "test",
        special = "with\nnewlines",
        empty = "",
    }

    -- Test normal string dumping
    local result1 = dump(t)
    assert.equal(result1, [[{
    empty = "",
    normal = "test",
    special = "with\
newlines"
}]])

    -- Test with filter that modifies string handling (nodump case)
    local result2 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'val' and vtype == 'string' and key == 'special' then
            return 'MODIFIED', true -- nodump = true for this case
        end
        return val
    end)
    assert.equal(result2, [[{
    empty = "",
    normal = "test",
    special = MODIFIED
}]])
end

function testcase.dump_other_value_types()
    -- test handling of other value types that fall through to final else clause

    local function test_function()
    end
    local thread = coroutine.create(function()
    end)

    local t = {
        func = test_function,
        thread = thread,
    }

    -- Test with filter that returns non-standard types for val
    local result = dump(t, nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if use == 'val' and vtype == 'function' then
            -- Return a userdata-like object that will trigger the final else clause
            return setmetatable({}, {
                __tostring = function()
                    return "custom_func"
                end,
            })
        end
        return val
    end)

    -- func should be an empty table {}, thread contains dynamic address
    assert.equal(result, ([[{
    func = {},
    thread = "thread: %s"
}]]):format(tostring(thread):match("thread: (.+)")))
end

function testcase.dump_boolean_key_sorting()
    -- test boolean key sorting in sort_index function
    local t = {
        [true] = "true_value",
        [false] = "false_value",
    }
    local result = dump(t)
    assert.equal(result, [[{
    [false] = "false_value",
    [true] = "true_value"
}]])
end

function testcase.dump_circular_number_boolean_cases()
    -- test circular reference with number/boolean return types
    local t = {}
    t.self = t

    -- Test circular filter returning number
    local result1 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return 42 -- number type
        end
        return val
    end)
    assert.equal(result1, [[{
    self = 42
}]])

    -- Test circular filter returning boolean
    local result2 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return true -- boolean type
        end
        return val
    end)
    assert.equal(result2, [[{
    self = true
}]])

    -- Test circular filter returning other type (should go to final else)
    local retfn = function()
    end
    local result3 = dump(t, nil, nil,
                         function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return retfn -- function type - triggers final else
        end
        return val
    end)
    -- Function addresses are dynamic, so we check for the pattern
    assert.equal(result3, ([[{
    self = "function: %s"
}]]):format(tostring(retfn):match("function: (.+)")))
end

function testcase.dump_table_key_with_filter()
    -- test table key with nokdump=true to trigger alternative path
    local key_table = {
        key = "value",
    }
    local t = {
        [key_table] = "test",
    }

    local result = dump(t, nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if use == 'key' and vtype == 'table' then
            return val, true -- nokdump = true for table key
        end
        return val
    end)

    -- Should contain the tostring representation of table (with dynamic address)
    assert.equal(result, ([[{
    [%q] = "test"
}]]):format(tostring(key_table)))
end

function testcase.dump_val_with_novdump()
    -- test value with novdump=true for table type
    local inner_table = {
        inner = "value",
    }
    local t = {
        nested = inner_table,
    }

    local result = dump(t, nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if use == 'val' and vtype == 'table' and key == 'nested' then
            return val, true -- novdump = true for table value
        end
        return val
    end)

    -- Should contain quoted tostring representation (with dynamic address)
    assert.equal(result, ([[{
    nested = %q
}]]):format(tostring(inner_table)))
end

function testcase.dump_circular_nodump_table()
    -- test circular reference with filter returning table and nodump=true
    local t = {}
    t.self = t

    local rettbl = {
        dummy = "table",
    }
    local result = dump(t, nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if use == 'circular' then
            return rettbl, true -- return table with nodump=true
        end
        return val
    end)

    -- Should trigger the tostring(val) path for nodump table (with dynamic address)
    assert.equal(result, ([[{
    self = %q
}]]):format(tostring(rettbl)))
end

function testcase.dump_mixed_key_types_sorting()
    -- test sorting of mixed key types to cover string comparison branches
    local function test_func()
    end
    local thread = coroutine.create(function()
    end)
    local userdata = setmetatable({}, {
        __tostring = function()
            return "userdata"
        end,
    })

    -- Create a table with mixed key types that will trigger string comparison branches
    -- The key is to have combinations that force string vs non-string comparisons
    local t = {
        -- Mix of different key types to trigger all sorting branches
        [1] = "number_key",
        [2] = "another_number",
        [true] = "boolean_key_true",
        [false] = "boolean_key_false",
        ["aaa_string"] = "string_value_a",
        ["zzz_string"] = "string_value_z",
        [test_func] = "function_key",
        [thread] = "thread_key",
        [userdata] = "userdata_key",
    }

    local result = dump(t)

    -- Verify all keys are present and properly formatted
    assert.equal(result, ([[{
    [1] = "number_key",
    [2] = "another_number",
    [false] = "boolean_key_false",
    [true] = "boolean_key_true",
    [%q] = "function_key",
    [%q] = "thread_key",
    [{}] = "userdata_key",
    aaa_string = "string_value_a",
    zzz_string = "string_value_z"
}]]):format(tostring(test_func), tostring(thread)))

    -- Additional test to specifically trigger string vs non-string comparison
    local t2 = {
        [userdata] = "userdata_first",
        ["middle_string"] = "string_middle",
        [test_func] = "function_last",
    }

    local result2 = dump(t2)
    -- String keys should come after other types in the sorting order
    assert.equal(result2, ([[{
    [%q] = "function_last",
    [{}] = "userdata_first",
    middle_string = "string_middle"
}]]):format(tostring(test_func)))
end

function testcase.dump_string_vs_other_type_sorting()
    -- Specifically test string vs other types to trigger the uncovered branches
    local func = function()
        return "test"
    end
    local thread = coroutine.create(function()
    end)

    -- Create a table that forces string vs function/thread comparisons
    local t1 = {
        [func] = "function_value",
        ["string_key"] = "string_value",
    }

    local result1 = dump(t1)
    assert.equal(result1, ([[{
    [%q] = "function_value",
    string_key = "string_value"
}]]):format(tostring(func)))

    -- Test string vs thread
    local t2 = {
        [thread] = "thread_value",
        ["another_string"] = "another_value",
    }

    local result2 = dump(t2)
    assert.equal(result2, ([[{
    [%q] = "thread_value",
    another_string = "another_value"
}]]):format(tostring(thread)))

    -- Test with only function keys to trigger the final "return false"
    local func1 = function()
        return 1
    end
    local func2 = function()
        return 2
    end

    local t3 = {
        [func1] = "func1_value",
        [func2] = "func2_value",
    }

    local result3 = dump(t3)
    if tostring(func1) < tostring(func2) then
        assert.equal(result3, ([[{
    [%q] = "func1_value",
    [%q] = "func2_value"
}]]):format(tostring(func1), tostring(func2)))
    else
        assert.equal(result3, ([[{
    [%q] = "func2_value",
    [%q] = "func1_value"
}]]):format(tostring(func2), tostring(func1)))
    end
end

function testcase.dump_filtered_key_sorting()
    for _, input_key in ipairs({
        1,
        false,
        {},
    }) do
        local result = dump({
            [input_key] = "converted",
            z = "unchanged",
        }, nil, nil, function(val, depth, vtype, use)
            if use == 'key' and val == input_key then
                return 'alpha'
            end
            return val
        end)
        assert.equal(result, [[{
    alpha = "converted",
    z = "unchanged"
}]])
    end
end

function testcase.dump_renamed_string_key_sorting()
    local names = {
        a = 'z',
        z = 'a',
    }
    local result = dump({
        a = 1,
        z = 2,
    }, nil, nil, function(val, depth, vtype, use)
        if use == 'key' then
            return names[val]
        end
        return val
    end)
    assert.equal(result, [[{
    a = 2,
    z = 1
}]])
end

function testcase.dump_distinct_tables_with_same_tostring()
    local mt = {
        __tostring = function()
            return 'same'
        end,
    }
    local child = setmetatable({ value = 1 }, mt)
    child.self = child
    local root = setmetatable({ child = child }, mt)
    assert.equal(dump(root, 0),
                 '{ child = { self = "<Circular same>", value = 1 } }')

    -- A shared table is expanded again after leaving its earlier occurrence.
    root = { a = child, b = child }
    assert.equal(dump(root, 0),
                 '{ a = { self = "<Circular same>", value = 1 }, ' ..
                 'b = { self = "<Circular same>", value = 1 } }')
end

function testcase.dump_distinct_table_keys_with_same_tostring()
    local mt = {
        __tostring = function()
            return 'same'
        end,
    }
    local key = setmetatable({ name = 'key' }, mt)
    key.self = key
    local root = setmetatable({ [key] = 'value' }, mt)
    assert.equal(dump(root, 0),
                 '{ [{ name = "key", self = "<Circular same>" }] = "value" }')
end

function testcase.dump_circular_marker_escaping()
    for _, label in ipairs({
        'plain',
        'double "quote"',
        "single 'quote'",
        'back\\slash',
        'line\nbreak',
        '\0\1\31\127',
        ']] ]=]',
    }) do
        local t = setmetatable({}, {
            __tostring = function()
                return label
            end,
        })
        t.self = t
        local marker = '<Circular ' .. label .. '>'
        local result = dump(t, 0)
        assert.equal(result, ('{ self = %q }'):format(marker))
        local chunk, err = (loadstring or load)('return ' .. result)
        assert(chunk, err)
        assert.equal(chunk().self, marker)
    end
end

function testcase.dump_circular_key_marker_escaping()
    for _, label in ipairs({
        'double "quote"',
        'back\\slash',
        'line\nbreak',
        '\0\1\31\127',
    }) do
        local mt = { __tostring = function() return label end }
        local key = setmetatable({}, mt)
        key.self = key
        local root = { [key] = 'value' }
        local marker = '<Circular ' .. label .. '>'
        local result = dump(root, 0)
        local chunk, err = (loadstring or load)('return ' .. result)
        assert(chunk, err)
        local dumped_key, dumped_value = next(chunk())
        assert.equal(dumped_key.self, marker)
        assert.equal(dumped_value, 'value')

        -- The circular marker can itself become the output key.
        root = setmetatable({}, mt)
        root[root] = 'root key'
        result = dump(root, 0)
        chunk, err = (loadstring or load)('return ' .. result)
        assert(chunk, err)
        assert.equal(chunk()[marker], 'root key')
    end
end

function testcase.dump_circular_tostring_marker()
    local t = setmetatable({}, {
        __tostring = function()
            return 'custom "table"'
        end,
    })
    t.self = t
    assert.equal(dump(t, 0),
                 ('{ self = %q }'):format('<Circular ' .. tostring(t) .. '>'))
end

function testcase.dump_shared_table_is_not_circular()
    local shared = {
        value = 1,
    }
    local result = dump({
        a = shared,
        b = shared,
    })
    assert.equal(result, [[{
    a = {
        value = 1
    },
    b = {
        value = 1
    }
}]])
end

local function circular_marker(value)
    return string.format('%q', '<Circular ' .. tostring(value) .. '>')
end

function testcase.dump_reftrack()
    local t1 = {
        hello = {
            world = "test",
        },
    }
    local t2 = {
        ref = {
            foo = {
                t1.hello,
            },
        },
    }
    t1.hello.t2 = t2
    t2.ref.bar = t2.ref
    local result = dump(t1, nil, nil, nil, nil, true)
    assert.equal(result, ([=[{ --[[%s]]
    hello = { --[[%s]]
        t2 = { --[[%s]]
            ref = { --[[%s]]
                bar = "<Circular %s>",
                foo = { --[[%s]]
                    [1] = "<Circular %s>"
                }
            }
        },
        world = "test"
    }
}]=]):format(tostring(t1), tostring(t1.hello), tostring(t2),
             tostring(t2.ref), tostring(t2.ref), tostring(t2.ref.foo),
             tostring(t1.hello)) .. '\n--[[Circular References:\n-- In Values:\n' ..
                     '$.hello.t2.ref.bar = ' .. circular_marker(t2.ref) .. '\n' ..
                     '$.hello.t2.ref.foo[1] = ' .. circular_marker(t1.hello) .. '\n]]')
end

function testcase.dump_reftrack_single_line()
    local t = {}
    t.self = t
    local result = dump(t, 0, nil, nil, nil, true)
    assert.equal(result, ('{ --[[%s]] self = %q }; '):format(
                     tostring(t), '<Circular ' .. tostring(t) .. '>') ..
                     '--[[Circular References: -- In Values: $.self = ' .. circular_marker(t) .. ' ]]')
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    assert.equal(chunk().self, '<Circular ' .. tostring(t) .. '>')
end

function testcase.dump_reftrack_flags()
    local t = {}
    t.self = t
    assert.equal(dump(t, 0, nil, nil, nil, false), dump(t, 0))
    local empty = {}
    assert.equal(dump(empty, 0, nil, nil, nil, true),
                 ('{ --[[%s]]}; --[[Circular References:  ]]'):format(tostring(empty)))
    assert.equal(dump(42, nil, nil, nil, nil, true), '42')
    for _, flag in ipairs({
        0,
        'true',
        {},
    }) do
        local err = assert.throws(function()
            dump({}, nil, nil, nil, nil, flag)
        end)
        assert.contains(err, 'reftrack must be boolean')
    end
end

function testcase.dump_circular_special_key_paths()
    for _, key in ipairs({
        'has space',
        'a"b',
        'a\\b',
        '\nkey',
        '\0key',
        ']]',
        ']=]',
        ']] ]=] ]==]',
    }) do
        local inner = {}
        inner.self = inner
        local value = {
            [key] = inner,
        }
        local pathname = '$[' .. string.format('%q', key) .. ']'
        for _, tracking in ipairs({
            false,
            true,
        }) do
            local result = dump(value, 0, nil, nil, nil, tracking)
            local chunk, err = (loadstring or load)('return ' .. result)
            assert(chunk, err)
            assert.equal(chunk()[key].self, '<Circular ' .. tostring(inner) .. '>')
            if tracking then
                assert.contains(result, 'Circular References:')
                assert.contains(result, '$' .. pathname:sub(2) ..
                                    '.self = ' .. circular_marker(inner))
            else
                assert.not_contains(result, 'Circular References:')
            end
        end
    end
end

function testcase.dump_reftrack_circular_filter()
    local t = {}
    t.self = t
    local result = dump(t, 0, nil, function(val, depth, vtype, use)
        if use == 'circular' then
            return 42
        end
        return val
    end, nil, true)
    assert.equal(result,
                 ('{ --[[%s]] self = 42 }; --[[Circular References:  ]]'):format(tostring(t)))
end

function testcase.dump_circular_table_key_paths()
    local key = { name = 'key' }
    local value = {}
    value.self = value
    local result = dump({ [key] = value }, 0)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local dumped_key, dumped_value = next(chunk())
    assert.equal(dumped_key.name, 'key')
    assert.equal(dumped_value.self, '<Circular ' .. tostring(value) .. '>')

    key.self = key
    result = dump({ [key] = 'value' }, 0)
    chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    dumped_key, dumped_value = next(chunk())
    assert.equal(dumped_key.self, '<Circular ' .. tostring(key) .. '>')
    assert.equal(dumped_value, 'value')
end

function testcase.dump_circular_table_key_to_root()
    local root = {}
    local key = { child = { data = root } }
    root[key] = 'value'
    local result = dump(root, 0)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local dumped_key = next(chunk())
    assert.equal(dumped_key.child.data, '<Circular ' .. tostring(root) .. '>')
end

function testcase.dump_circular_table_key_escaping()
    local value = setmetatable({}, {
        __tostring = function()
            return 'custom "name"\n]]'
        end,
    })
    value.self = value
    local result = dump({ [{}] = { child = value } }, 0)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local _, dumped_value = next(chunk())
    assert.equal(dumped_value.child.self,
                 '<Circular custom "name"\n]]>')
end

function testcase.dump_reftrack_preserves_dump_body()
    local root = { foo = {} }
    root.foo.self = root.foo
    root.foo.root = root
    local body = dump(root, 0)
    assert.equal(dump(root, 0, nil, nil, nil, false), body)
    local tracked = dump(root, 0, nil, nil, nil, true)
    local expected = ('{ --[[%s]] foo = { --[[%s]] root = %q, self = %q } }'):format(
        tostring(root), tostring(root.foo), '<Circular ' .. tostring(root) .. '>',
        '<Circular ' .. tostring(root.foo) .. '>')
    assert.equal(tracked, expected .. tracking_comment({
        '$.foo.root = ' .. circular_marker(root),
        '$.foo.self = ' .. circular_marker(root.foo),
    }, {}, true))
    local chunk, err = (loadstring or load)('return ' .. tracked)
    assert(chunk, err)
    local value = chunk()
    assert.equal(value.foo.self, '<Circular ' .. tostring(root.foo) .. '>')
    assert.equal(value.foo.root, '<Circular ' .. tostring(root) .. '>')
end

function testcase.dump_reftrack_table_key_self()
    local key = {}
    key.self = key
    local root = { foo = { [key] = 'value' } }
    local label = string.format('%q', '<' .. tostring(key) .. '>')
    local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $.foo'
    assert_tracking(dump(root, 0, nil, nil, nil, true), {}, { row }, true)
end

function testcase.dump_reftrack_nested_table_keys()
    local root = { foo = {} }
    local key = { child = {} }
    local innerkey = {}
    key.child.data = root
    key.child.self = key.child
    key[innerkey] = 'inner'
    innerkey.self = innerkey
    root.foo[key] = 'value'
    local outer = string.format('%q', '<' .. tostring(key) .. '>')
    local inner = string.format('%q', '<' .. tostring(innerkey) .. '>')
    local child = circular_marker(key.child)
    local rows = {
        '[{ ' .. outer .. '.child.data = ' .. circular_marker(root) .. ' }] @ $.foo',
        '[{ ' .. outer .. '.child.self = ' .. child .. ' }] @ $.foo',
        '[{ ' .. outer .. '[{ ' .. inner .. '.self = ' .. circular_marker(innerkey) .. ' }] }] @ $.foo',
    }
    table.sort(rows)
    assert_tracking(dump(root, 0, nil, nil, nil, true), {}, rows, true)
end

function testcase.dump_reftrack_root_as_key()
    local root = {}
    root[root] = 'value'
    local label = string.format('%q', '<' .. tostring(root) .. '>')
    local row = '[{ ' .. label .. ' = ' .. circular_marker(root) .. ' }] @ $'
    assert_tracking(dump(root, 0, nil, nil, nil, true), {}, { row }, true)
end

function testcase.dump_reftrack_table_key_quotes()
    local key = setmetatable({}, {
        __tostring = function()
            return 'key "quoted"\n]] ]=]'
        end,
    })
    key.self = key
    local root = { [key] = 'value' }
    local label = string.format('%q', '<table: ' .. tostring(key) .. '>')
    local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $'
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, {}, { row }, true)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local dumped_key = next(chunk())
    assert.equal(dumped_key.self, '<Circular ' .. tostring(key) .. '>')
end

function testcase.dump_reftrack_table_key_identity()
    local mt = { __tostring = function() return 'same' end }
    local key1 = setmetatable({ name = 'first' }, mt)
    local key2 = setmetatable({ name = 'second' }, mt)
    key1.self = key1
    key2.self = key2
    local root = { [key1] = 'one', [key2] = 'two' }
    local row = '[{ "<table: same>".self = "<Circular same>" }] @ $'
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, {}, { row, row }, true)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local found = {}
    for key, value in pairs(chunk()) do
        found[key.name] = value
        assert.equal(key.self, '<Circular same>')
    end
    assert.equal(found.first, 'one')
    assert.equal(found.second, 'two')
end

function testcase.dump_untracked_table_key_tostring()
    local calls = 0
    local key = setmetatable({ name = 'key' }, {
        __tostring = function()
            calls = calls + 1
            return 'key'
        end,
    })
    local root = { [key] = 'value' }
    local expected = '{ [{ name = "key" }] = "value" }'
    assert.equal(dump(root, 0), expected)
    assert.equal(calls, 1)
    calls = 0
    assert.equal(dump(root, 0, nil, nil, nil, false), expected)
    assert.equal(calls, 1)
end

function testcase.dump_reftrack_key_and_value_paths_are_independent()
    local key = {}
    key.self = key
    local value = { key = key }
    value.self = value
    local root = { [key] = 'value', foo = value }
    local label = string.format('%q', '<' .. tostring(key) .. '>')
    local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $'
    assert_tracking(dump(root, nil, nil, nil, nil, true), {
        '$.foo.key.self = ' .. circular_marker(key),
        '$.foo.self = ' .. circular_marker(value),
    }, { row }, false)
end

function testcase.dump_reftrack_value_path_across_groups()
    for _, keygroup in ipairs({ 1, 2 }) do
        local key = {}
        key.self = key
        local valuegroup = 3 - keygroup
        local root = {
            [keygroup] = { [key] = 'value' },
            [valuegroup] = { key = key },
        }
        local target = '$[' .. valuegroup .. '].key'
        local label = string.format('%q', '<' .. tostring(key) .. '>')
        local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $[' ..
                        keygroup .. ']'
        local result = dump(root, 0, nil, nil, nil, true)
        assert_tracking(result, { target .. '.self = ' .. circular_marker(key) }, { row }, true)
    end
end

function testcase.dump_reftrack_multiple_value_paths()
    for _, names in ipairs({ { 'a', 'z' }, { 2, 10 } }) do
        local shared = {}
        shared.self = shared
        local root = { [names[1]] = shared, [names[2]] = shared }
        local paths = {}
        for _, name in ipairs(names) do
            paths[#paths + 1] = type(name) == 'number' and
                                   ('$[' .. name .. ']') or ('$.' .. name)
        end
        table.sort(paths)
        local rows = {
            paths[1] .. '.self = ' .. circular_marker(shared),
            paths[2] .. '.self = ' .. circular_marker(shared),
        }
        assert_tracking(dump(root, 0, nil, nil, nil, true), rows, {}, true)
    end
end

function testcase.dump_reftrack_only_expanded_value_paths()
    for _, mode in ipairs({ 'omit', 'nodump', 'rename' }) do
        local key = {}
        key.self = key
        local root = { [key] = 'value', foo = { key = key } }
        local function filter(val, depth, vtype, use, field)
            if use == 'key' and val == 'key' and mode == 'rename' then
                return 'renamed'
            elseif use == 'val' and field == 'key' then
                if mode == 'omit' then
                    return nil
                elseif mode == 'nodump' then
                    return val, true
                end
            end
            return val
        end
        local label = string.format('%q', '<' .. tostring(key) .. '>')
        local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $'
        local values = mode == 'rename' and
                           { '$.foo.renamed.self = ' .. circular_marker(key) } or {}
        local result = dump(root, 0, nil, filter, nil, true)
        assert_tracking(result, values, { row }, true)
        assert.not_contains(result, '= $.foo.key')
    end
end

function testcase.dump_reftrack_key_subtree_is_not_value_path()
    local shared = {}
    shared.self = shared
    local key1 = { child = shared }
    local key2 = { child = shared }
    local root = { [key1] = 'one', [key2] = 'two' }
    local rows = {}
    local target = circular_marker(shared)
    for _, key in ipairs({ key1, key2 }) do
        local label = string.format('%q', '<' .. tostring(key) .. '>')
        rows[#rows + 1] = '[{ ' .. label .. '.child.self = ' .. target .. ' }] @ $'
    end
    table.sort(rows)
    assert_tracking(dump(root, 0, nil, nil, nil, true), {}, rows, true)
end

function testcase.dump_reftrack_quoted_value_path()
    local key = {}
    key.self = key
    local field = 'quoted.@"field" ]]'
    local root = { [key] = 'value', [field] = key }
    local target = '$[' .. string.format('%q', field) .. ']'
    local label = string.format('%q', '<' .. tostring(key) .. '>')
    local row = '[{ ' .. label .. '.self = ' .. circular_marker(key) .. ' }] @ $'
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, { target .. '.self = ' .. circular_marker(key) }, { row }, true)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    assert.equal(chunk()[field].self, '<Circular ' .. tostring(key) .. '>')
end

function testcase.dump_reftrack_nested_key_value_paths()
    local inner = {}
    inner.self = inner
    local outer = { child = { [inner] = 'inner' } }
    outer.self = outer
    local root = { foo = { [outer] = 'outer' }, outer = outer, inner = inner }
    local outerlabel = string.format('%q', '<' .. tostring(outer) .. '>')
    local innerlabel = string.format('%q', '<' .. tostring(inner) .. '>')
    local keys = {
        '[{ ' .. outerlabel .. '.child[{ ' .. innerlabel .. '.self = ' ..
            circular_marker(inner) .. ' }] }] @ $.foo',
        '[{ ' .. outerlabel .. '.self = ' .. circular_marker(outer) .. ' }] @ $.foo',
        '[{ ' .. innerlabel .. '.self = ' .. circular_marker(inner) .. ' }] @ $.outer.child',
    }
    table.sort(keys)
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, {
        '$.inner.self = ' .. circular_marker(inner),
        '$.outer.self = ' .. circular_marker(outer),
    }, keys, true)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    assert.equal(chunk().inner.self, '<Circular ' .. tostring(inner) .. '>')
end

function testcase.dump_reftrack_value_under_table_key()
    local key = { name = 'key' }
    local value = {}
    value.self = value
    local root = { [key] = value }
    local path = '$[' .. string.format('%q', tostring(key)) .. ']<' .. string.format('%q', tostring(value)) .. '>'
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, { path .. '.self = ' .. circular_marker(value) }, {}, true)
    assert.not_contains(result, '-- In Keys:')
end


function testcase.dump_reftrack_key_to_active_value_ancestor()
    local root = { foo = {} }
    local key = { parent = root.foo }
    root.foo[key] = 'value'
    local label = string.format('%q', '<' .. tostring(key) .. '>')
    local row = '[{ ' .. label .. '.parent = ' .. circular_marker(root.foo) .. ' }] @ $.foo'
    assert_tracking(dump(root, 0, nil, nil, nil, true), {}, { row }, true)
end


function testcase.dump_reftrack_distinct_empty_table_key_paths()
    local key1, key2 = {}, {}
    local value1, value2 = {}, {}
    value1.self = value1
    value2.self = value2
    local root = { [key1] = value1, [key2] = value2 }
    local rows = {}
    for key, value in pairs(root) do
        local path = '$[' .. string.format('%q', tostring(key)) .. ']<' .. string.format('%q', tostring(value)) .. '>'
        rows[#rows + 1] = path .. '.self = ' .. circular_marker(value)
    end
    table.sort(rows)
    for _, nodump in ipairs({ false, true }) do
        local function filter(val, depth, vtype, use)
            return val, use == 'key' and nodump
        end
        local result = dump(root, 0, nil, filter, nil, true)
        local parsed = assert_tracking(result, rows, {}, true)
        local count = 0
        local markers = {}
        for _, value in pairs(parsed) do
            count = count + 1
            markers[value.self] = true
        end
        assert.equal(count, 2)
        assert(markers['<Circular ' .. tostring(value1) .. '>'])
        assert(markers['<Circular ' .. tostring(value2) .. '>'])
    end
end

function testcase.dump_reftrack_nested_table_key_value_path_escaping()
    local outerkey = {}
    local innerkey = setmetatable({}, {
        __tostring = function() return 'key "quoted"\n]]' end,
    })
    local value = {}
    local outervalue = { [innerkey] = value }
    value.self = value
    local root = { [outerkey] = outervalue }
    local path = '$'
    for _, key in ipairs({ outerkey, innerkey }) do
        local label = (key == innerkey and 'table: ' or '') .. tostring(key)
        local item = key == outerkey and outervalue or value
        path = path .. '[' .. string.format('%q', label) .. ']<' ..
                   string.format('%q', tostring(item)) .. '>'
    end
    local result = dump(root, 0, nil, nil, nil, true)
    assert_tracking(result, { path .. '.self = ' .. circular_marker(value) }, {}, true)
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local _, parsedouter = next(chunk())
    local _, innervalue = next(parsedouter)
    assert.equal(innervalue.self, '<Circular ' .. tostring(value) .. '>')
end


function testcase.dump_reftrack_table_identity_comments()
    local key, value, child = {}, {}, {}
    value.self = value
    child.self = child
    local root = { child = child, values = { [key] = value } }
    local path = '$.values[' .. string.format('%q', tostring(key)) .. ']<' ..
                     string.format('%q', tostring(value)) .. '>'
    local expected = ('{ --[[%s]] child = { --[[%s]] self = %q }, ' ..
                      'values = { --[[%s]] [{ --[[%s]]}] = { --[[%s]] self = %q } } }'):format(
        tostring(root), tostring(child), '<Circular ' .. tostring(child) .. '>',
        tostring(root.values), tostring(key), tostring(value),
        '<Circular ' .. tostring(value) .. '>')
    local result = dump(root, 0, nil, nil, nil, true)
    assert.equal(result, expected .. tracking_comment({
        '$.child.self = ' .. circular_marker(child),
        path .. '.self = ' .. circular_marker(value),
    }, {}, true))
    local chunk, err = (loadstring or load)('return ' .. result)
    assert(chunk, err)
    local parsed = chunk()
    assert.equal(parsed.child.self, '<Circular ' .. tostring(child) .. '>')
    local parsedkey, parsedvalue = next(parsed.values)
    assert.equal(next(parsedkey), nil)
    assert.equal(parsedvalue.self, '<Circular ' .. tostring(value) .. '>')
end

function testcase.dump_reftrack_shared_and_empty_identity_comments()
    local shared = { n = 1 }
    local root = { a = shared, b = shared }
    local expected = ('{ --[[%s]] a = { --[[%s]] n = 1 }, b = { --[[%s]] n = 1 } }'):format(
        tostring(root), tostring(shared), tostring(shared))
    assert.equal(dump(root, 0, nil, nil, nil, true),
                 expected .. tracking_comment({}, {}, true))
    local empty = {}
    assert.equal(dump(empty, 0, nil, nil, nil, true),
                 ('{ --[[%s]]}'):format(tostring(empty)) ..
                     tracking_comment({}, {}, true))
    assert.equal(dump(empty, 0), '{}')
    assert.equal(dump(empty, 0, nil, nil, nil, false), '{}')
end

function testcase.dump_reftrack_identity_comment_escaping()
    local label = 'custom "table"\n]] ]=]'
    local value = setmetatable({}, {
        __tostring = function() return label end,
    })
    value.self = value
    for _, indent in ipairs({ 0, 2 }) do
        local result = dump(value, indent, nil, nil, nil, true)
        assert.contains(result, '{ --[==[table: ' .. label .. ']==]')
        local chunk, err = (loadstring or load)('return ' .. result)
        assert(chunk, err)
        assert.equal(chunk().self, '<Circular ' .. label .. '>')
    end
end


function testcase.dump_reftrack_typed_labels()
    for _, label in ipairs({ 'Node', 'table: Node', 'table: 0x1234', '' }) do
        local calls = 0
        local key = setmetatable({}, {
            __tostring = function()
                calls = calls + 1
                return label
            end,
        })
        key.self = key
        local root = { [key] = 'value' }
        local typed = label == 'Node' and 'table: Node' or
                          (label == '' and 'table: ' or label)
        local quoted = string.format('%q', '<' .. typed .. '>')
        local row = '[{ ' .. quoted .. '.self = ' .. circular_marker(key) .. ' }] @ $'
        calls = 0
        local result = dump(root, 0, nil, nil, nil, true)
        assert.equal(calls, 3)
        local parsed = assert_tracking(result, {}, { row }, true)
        assert.contains(result, '--[[' .. typed .. ']]')
        assert.equal(next(parsed).self, '<Circular ' .. label .. '>')
        calls = 0
        result = dump(root, 0)
        assert.equal(calls, 2)
        assert.not_contains(result, 'Circular References:')
        local chunk = builtin_assert((loadstring or load)('return ' .. result))
        assert.equal(next(chunk()).self, '<Circular ' .. label .. '>')
    end
end

function testcase.dump_reftrack_value_identity_annotation()
    local key = setmetatable({}, {
        __tostring = function() return 'Key "name"' end,
    })
    local value = setmetatable({}, {
        __tostring = function() return 'Value > "name"' end,
    })
    value.self = value
    local root = { values = { [key] = value } }
    local path = '$.values["table: Key \\"name\\""]<"table: Value > \\"name\\"">'
    local row = path .. '.self = "<Circular Value > \\"name\\">"'
    for _, indent in ipairs({ 0, 2 }) do
        local parsed = assert_tracking(dump(root, indent, nil, nil, nil, true),
                                       { row }, {}, indent == 0)
        local _, item = next(parsed.values)
        assert.equal(item.self, '<Circular Value > "name">')
    end
end

function testcase.dump_reftrack_replaced_value_identity()
    for _, insidekey in ipairs({ false, true }) do
        local key, source, replacement = {}, {}, {}
        source[key] = source
        replacement.self = replacement
        local root = insidekey and { [source] = 'outer' } or source
        local function filter(v, depth, typ, use)
            if use == 'circular' and v == source then
                return replacement
            end
            return v
        end
        local suffix = '[' .. string.format('%q', tostring(key)) .. ']<' ..
                           string.format('%q', tostring(replacement)) ..
                           '>.self = ' .. circular_marker(replacement)
        local values, keys = {}, {}
        if insidekey then
            keys[1] = '[{ ' .. string.format('%q', '<' .. tostring(source) .. '>') ..
                          suffix .. ' }] @ $'
        else
            values[1] = '$' .. suffix
        end
        for _, indent in ipairs({ 0, 2 }) do
            local result = dump(root, indent, nil, filter, nil, true)
            local parsed = assert_tracking(result, values, keys, indent == 0)
            local parent = insidekey and next(parsed) or parsed
            local _, item = next(parent)
            assert.equal(item.self, '<Circular ' .. tostring(replacement) .. '>')
        end
    end
end

function testcase.dump_reftrack_circular_value_identity()
    local key, root = {}, {}
    root[key] = root
    local row = '$[' .. string.format('%q', tostring(key)) .. ']<' ..
                    string.format('%q', tostring(root)) .. '> = ' .. circular_marker(root)
    local parsed = assert_tracking(dump(root, 0, nil, nil, nil, true),
                                   { row }, {}, true)
    local _, marker = next(parsed)
    assert.equal(marker, '<Circular ' .. tostring(root) .. '>')
end

function testcase.dump_reftrack_value_identity_inside_key()
    local outer, inner, value = {}, {}, {}
    value.self = value
    outer[inner] = value
    local root = { [outer] = 'outer' }
    local row = '[{ ' .. string.format('%q', '<' .. tostring(outer) .. '>') ..
                    '[' .. string.format('%q', tostring(inner)) .. ']<' ..
                    string.format('%q', tostring(value)) .. '>.self = ' ..
                    circular_marker(value) .. ' }] @ $'
    local parsed = assert_tracking(dump(root, 0, nil, nil, nil, true),
                                   {}, { row }, true)
    local outerkey = next(parsed)
    local _, item = next(outerkey)
    assert.equal(item.self, '<Circular ' .. tostring(value) .. '>')
end

function testcase.dump_reftrack_table_key_sort_ignores_identity_comments()
    for _, nested in ipairs({ false, true }) do
        local first, second, child1, child2 = {}, {}, {}, {}
        if tostring(first) > tostring(second) then first, second = second, first end
        if tostring(child1) > tostring(child2) then child1, child2 = child2, child1 end
        if nested then
            first.child, second.child = child1, child2
            child1.name, child2.name = 'z', 'a'
        else
            first.name, second.name = 'z', 'a'
        end
        local root = { [first] = 'z', [second] = 'a' }
        for _, tracking in ipairs({ false, true }) do
            local result = dump(root, 0, nil, nil, nil, tracking)
            local apos = builtin_assert(result:find('name = "a"', 1, true))
            local zpos = builtin_assert(result:find('name = "z"', 1, true))
            assert(apos < zpos, 'table-key ordering must ignore identity comments')
        end
    end
end

function testcase.dump_reftrack_comment_like_string_payloads()
    local payload = '{ --[[payload]]}'
    local field = '{ --[[key]]}'
    for _, indent in ipairs({ 0, 2 }) do
        for _, tracking in ipairs({ false, true }) do
            local root = { text = payload, [field] = '{ --[=[value]=]}' }
            root.self = root
            local result = dump(root, indent, nil, nil, nil, tracking)
            local parsed
            if tracking then
                parsed = assert_tracking(result, { '$.self = ' .. circular_marker(root) }, {}, indent == 0)
            else
                local chunk, err = (loadstring or load)('return ' .. result)
                assert(chunk, err)
                parsed = chunk()
            end
            assert.equal(parsed.text, payload)
            assert.equal(parsed[field], '{ --[=[value]=]}')
            assert.equal(parsed.self, '<Circular ' .. tostring(root) .. '>')
        end
    end
end

-- Run described test cases
run_all_tests()
