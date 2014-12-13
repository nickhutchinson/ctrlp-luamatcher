let s:path = expand('<sfile>:p:h')

lua <<EOF
-- Reload our fuzzy_matcher... modules.
for k, _ in pairs(package.loaded) do
  if k:match("^fuzzy_matcher") then
    package.loaded[k] = nil
  end
end

local function is_in_path(p)
    for s in package.path:gmatch("[^;]+") do
        if s == p then return true end
    end
    return false
end

local script_dir = string.format('%s/../lua/?.lua', vim.eval('s:path'))

if not is_in_path(script_dir) then
    local prev = package.path
    package.path = string.format('%s;%s', script_dir, package.path)
    require 'fuzzy_matcher.matcher'
    package.path = prev
end
--------------------------------------------------------------------------------

fuzzy_lua_find_match = (function()
  local Matcher = require'fuzzy_matcher.matcher'

  local DEBUG = false
  local match_session = setmetatable({}, Matcher)

  -- Caching this appears to speed things up.
  local get_match_score = match_session.get_match_score

  local get_monotonic_nanos = (function()
    if not DEBUG then return function() return -1 end end

    -- FIXME: Linux timers too
    local ffi = require 'ffi'
    local C = ffi.C
    ffi.cdef[[ uint64_t mach_absolute_time(); ]]
    return function() return C.mach_absolute_time() end
  end)()

  local dprintf = (function()
    if not DEBUG then return function () end end

    local counter = 0
    local log_handle = io.open("/tmp/fuzzy_lua_log.txt", "a+")
    log_handle:setvbuf("line")

    return function(...)
      log_handle:write('[', tostring(counter), ']: ')
      log_handle:write(string.format(...), "\n")
      counter = counter + 1
    end
  end)()

  local vimlist_to_table = (function()
    -- Args:
    --   vimlist: a Vim list userdata
    -- Returns:
    --   An equivalent Lua table
    --
    -- Marshalling a big vim list (100,000 elems) into Lua takes 50ms. This
    -- happens every keystroke (and every time the user navigates up/down the
    -- list?!) It's worth caching the results.
    --
    -- XXX: This assumes it's safe to compare a vim list by identity -- it
    -- looks like CtrlP doesn't manipulate a list after creation, but it's
    -- something to look out for.
    local last_vimlist = nil
    local last_table = nil

    return function(vimlist)
      if vimlist == last_vimlist then
        return last_table
      end

      local tbl = {}
      for item in vimlist() do
        table.insert(tbl, item)
      end

      last_vimlist = vimlist
      last_table = tbl

      return tbl
    end
  end)()


  local function pcalled(f)
    return function (...)
      local success, result = pcall(f, ...)
      if not success then
        dprintf("Failed call: %s", result)
        return nil
      else
        return result
      end
    end
  end

  return pcalled(function(_A)
    local start = get_monotonic_nanos()

    local items_vimlist, str, limit, results_vimlist =
        _A[0], _A[1], _A[2], _A[3]

    local items = vimlist_to_table(items_vimlist)

    local sort_elapsed = 0
    local results_elapsed = 0

    local results = {}
    for _, item in ipairs(items) do
      local score = get_match_score(match_session, item, str)
      if score ~= 0 then table.insert(results, {item, score}) end
    end

    do
      local start = get_monotonic_nanos()
      table.sort(results, function(a, b) return a[2] > b[2] end)
      sort_elapsed = get_monotonic_nanos() - start
    end

    for i=1, math.min(#results, limit) do
      results_vimlist:add(results[i][1])
    end

    local elapsed = get_monotonic_nanos() - start

    dprintf("Fetch request elapsed: %dms { str= %s, limit= %d, inputsize= %d }",
            tonumber(elapsed) / 1000000, str, limit, #items)
    dprintf("Sort elapsed: %dms", tonumber(sort_elapsed)/1000000)
    dprintf("Raw result count: %d", #results)
  end)
end)()

EOF

function! fuzzylua#Match(items, str, limit, mmode, ispath, crfile, regex)
    let l:results = []
    let l:_ = luaeval("fuzzy_lua_find_match(_A)", [ a:items, a:str, a:limit, l:results])
    return l:results
    " Arguments:
    " |
    " +- a:items  : The full list of items to search in.
    " |
    " +- a:str    : The string entered by the user.
    " |
    " +- a:limit  : The max height of the match window. Can be used to limit
    " |             the number of items to return.
    " |
    " +- a:mmode  : The match mode. Can be one of these strings:
    " |             + "full-line": match the entire line.
    " |             + "filename-only": match only the filename.
    " |             + "first-non-tab": match until the first tab char.
    " |             + "until-last-tab": match until the last tab char.
    " |
    " +- a:ispath : Is 1 when searching in file, buffer, mru, mixed, dir, and
    " |             rtscript modes. Is 0 otherwise.
    " |
    " +- a:crfile : The file in the current window. Should be excluded from the
    " |             results when a:ispath == 1.
    " |
    " +- a:regex  : In regex mode: 1 or 0.
endfunction
