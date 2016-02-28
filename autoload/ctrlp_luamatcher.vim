let s:current_file_dir = expand('<sfile>:p:h')

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

local package_path_entry = string.format(
    '%s/../lua/?.lua', vim.eval('s:current_file_dir'))

if not is_in_path(package_path_entry) then
    local prev = package.path
    package.path = string.format('%s;%s', package_path_entry, package.path)
    require 'fuzzy_matcher.matcher'
    package.path = prev
end
--------------------------------------------------------------------------------

ctrlp_luamatcher_match_impl = (function()
  local Matcher = require'fuzzy_matcher.matcher'

  local DEBUG = false
  local matcher = Matcher()

  -- Caching this appears to speed things up.
  local match = matcher.match

  local monotonic_nanoseconds = (function()
    if not DEBUG then return function() return -1 end end

    -- FIXME: Support benchmarks on Linux too.
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
    -- Marshalling a big vim list (100,000 elems) into Lua can take 50ms. This
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
    local start = monotonic_nanoseconds()

    local candidates_vimlist, query, limit, results_vimlist =
        _A[0], _A[1], _A[2], _A[3]
    local candidates = vimlist_to_table(candidates_vimlist)

    local sort_elapsed = 0
    local results_elapsed = 0

    local results = {}
    for _, candidate in ipairs(candidates) do
      local score = match(matcher, query, candidate)
      if score ~= 0 then table.insert(results, {candidate, score}) end
    end

    do
      local start = monotonic_nanoseconds()
      table.sort(results, function(a, b)
        local result = a[2] - b[2]
        if result ~= 0 then
          return result > 0
        else
          return a[1] > b[1]
        end
      end)
      sort_elapsed = monotonic_nanoseconds() - start
    end

    for i=1, math.min(#results, limit) do
      results_vimlist:add(results[i][1])
    end

    local elapsed = monotonic_nanoseconds() - start

    dprintf("Fetch request elapsed: %dms " ..
            "{ query= %s, limit= %d, inputsize= %d }",
            tonumber(elapsed) / 1000000, query, limit, #candidates)
    dprintf("Sort elapsed: %dms", tonumber(sort_elapsed)/1000000)
    dprintf("Raw result count: %d", #results)
  end)
end)()

EOF

function! ctrlp_luamatcher#Match( candidates, query, limit, mmode, ispath,
      \ crfile, regex)
    let l:results = []
    let l:_ = luaeval(
          \ "ctrlp_luamatcher_match_impl(_A)",
          \ [ a:candidates, a:query, a:limit, l:results])
    return l:results

    " XXX For now, I'm not interested in handling anything except the
    " full-line mode.

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
