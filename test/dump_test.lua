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

function testcase.dump_non_table_value()
    -- test that non-table values are dumped correctly

    -- Test basic value types
    assert.equal(dump(nil), '"nil"')
    assert.equal(dump(true), '"true"')
    assert.equal(dump(false), '"false"')
    assert.equal(dump(123), '"123"')
    assert.equal(dump(123.45), '"123.45"')
    assert.equal(dump("hello"), '"hello"')

    -- Test with custom filter
    local result = dump("test", nil, nil,
                        function(val, depth, vtype, use, key, udata)
        if vtype == "string" then
            return val, true -- nodump = true
        end
        return val
    end)
    assert.equal(result, "test")
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

-- Run described test cases
run_all_tests()
