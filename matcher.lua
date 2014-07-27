--------------------------------------------------------------------------------
-- Make `require '.foo'` load 'foo.lua' relative to this script
local SCRIPT_DIR = (rawget(_G, 'arg')
    and arg[0]
    and arg[0]:gsub('[/\\]?[^/\\]+$', '')
    or '.')

local function relative_loader(modulename)
  print(SCRIPT_DIR, arg[0])
  local resolved_path, num_matches = string.gsub(
      modulename, "^%.(.*)$",
      function(tail)
        return string.format("%s/%s.lua", SCRIPT_DIR, tail)
      end
  )
  if num_matches == 1 then
    local mod, error_message = loadfile(resolved_path)
    return error_message and error_message or mod
  end
end

table.insert(package.loaders, relative_loader)
--------------------------------------------------------------------------------
require "./strict"

local FFIUtil = require "./ffi_util"
local Matrix = require "./matrix"
local Vector = require "./vector"
local Sort = require "./sort"
local ffi = require "ffi"

local function printf(...)
  print(string.format(...))
end

local DEBUG = arg[1] or false
local function NOOP() end

local dprintf = NOOP
if DEBUG then dprintf = printf end

local DEBUG_BOUNDS_CHECKING = false
--------------------------------------------------------------------------------
local value_type = ffi.typeof"double"

-- Converts character `ch` to its ascii value.
local function B(ch) return string.byte(ch, 1, 1) end

local function is_upper(ch) return B'A' <= ch and ch <= B'Z' end
local function is_lower(ch) return B'a' <= ch and ch <= B'z' end
local function is_digit(ch) return B'0' <= ch and ch <= B'9' end
local function is_alpha(ch) return is_upper(ch) or is_lower(ch) end
local function is_pathsep(ch) return ch == B'/' or ch == B'\\' end
local function is_sep(ch)
  return ch == B'/' or ch == B'\\' or ch == B' ' or ch == B'_' or ch == B'-'
end


local is_same_letter = (function()
  local function to_lower(ch)
    if is_upper(ch) then return ch + B'a' - B'A' else return ch end
  end

  local equiv_table = Vector("char")(256)
  for i = 0, 255 do
    equiv_table[i] = to_lower(i)
  end

  return function(ch1, ch2)
    assert(not DEBUG_BOUNDS_CHECKING or 0 <= ch1 and ch1 <= 255)
    assert(not DEBUG_BOUNDS_CHECKING or 0 <= ch2 and ch2 <= 255)
    return equiv_table[ch1] == equiv_table[ch2]
  end
end)()

local MatchSession = {
  __index = {
    -- #get_match_score()#
    -- Calculates the score if |needle| is to match the candidate string
    -- |haystack|.
    --
    -- Args:
    --   haystack {string}: The haystack.
    --   needle   {string}: The needle.
    --
    -- Returns:
    --   A {number} between 0.0 and 1.0.
    --   0.0 is returned when |needle| is not a subseqeuence of |haystack|;
    --   returns 1.0 if |needle| is the empty string.
    get_match_score = function(self, haystack, needle)
      dprintf("haystack: %s, needle: %s", haystack, needle)
      self:_prepare_for_match(haystack, needle)

      local m, n = #needle + 1, #haystack + 1
      local normalized_char_score = (1.0 / (m-1) + 1.0 / (n-1)) / 2

      local scoreboard = self._scoreboard
      local match_coefficients = self._match_coefficients
      local match_offsets, match_offsets_prev =
          self._match_offsets, self._match_offsets_prev

      local j_start = 0

      for i = 1, scoreboard.m - 1 do
        for j = j_start + 1, scoreboard.n - 1 do
          local ch_i, ch_j = string.byte(needle, i), string.byte(haystack, j)

          if not is_same_letter(ch_i, ch_j) then
            match_offsets[j] = match_offsets[j-1]
            scoreboard:set(i, j, math.max(scoreboard(i, j-1),
                                          scoreboard(i-1, j)))
          else
            j_start = math.min(j_start, j)

            local coefficient = match_coefficients[j]
            if coefficient == 0 then
              local distance = j - match_offsets_prev[j-1]
              assert(distance > 0)
              coefficient = 0.75 / distance
            end

            local cumulative_score = (scoreboard(i-1, j-1) +
                normalized_char_score * coefficient)
            scoreboard:set(i, j, cumulative_score)

            if cumulative_score >= scoreboard(i, match_offsets[j-1]) then
              match_offsets[j] = j
            else
              match_offsets[j] = match_offsets[j-1]
            end
          end
        end

        local row_had_match = (0 ~= match_offsets[scoreboard.n - 1])
        if not row_had_match then return 0.0 end

        match_offsets_prev, match_offsets = match_offsets, match_offsets_prev
        match_offsets[j_start] = 0
      end

      return scoreboard(scoreboard.m-1, scoreboard.n-1)
    end,

    -- #_prepare_for_match()#
    -- Resets the internal state before a run; ensures the match vectors, as
    -- well as the scoreboard matrix are allocated.
    -- Args:
    --   haystack {string}:
    --   needle {string}:
    _prepare_for_match = function(self, haystack, needle)
      local m, n = #needle + 1, #haystack + 1
      self:_reset_vector('_match_offsets', n)
      self:_reset_vector('_match_offsets_prev', n)
      self:_reset_matrix('_scoreboard', m, n)
      self:_reset_vector('_match_coefficients', n)
      self:_calculate_match_coefficients(haystack)
    end,

    _reset_matrix = function(self, name, m, n)
      local mat = self[name]
      if not mat or mat.capacity < m * n then
        mat = Matrix(value_type)(m, n)
        self[name] = mat
      else
        mat:reshape(m, n)
      end
    end,

    _reset_vector = function(self, name, n)
      local vec = self[name]
      if not vec or vec.capacity < n then
        vec = Vector(value_type)(n)
        self[name] = vec
      end
      vec.length = n
    end,

    -- #_calculate_match_coefficients()#
    -- Initialises the _match_coefficients array.
    -- Args:
    --   haystack {Vector}: the haystack vector
    _calculate_match_coefficients = (function()
      local CharType = {
        Lower = 1, PathSep = 2, OtherSep = 3, Dot = 4, Other = 0,
      }
      return function(self, haystack)
        local n = #haystack + 1
        local coefficients = self._match_coefficients
        local kind = CharType.PathSep
        for i = 1, n - 1 do
          local ch = string.byte(haystack, i)
          local last_kind = kind

          if     is_lower(ch)   then kind = CharType.Lower
          elseif is_pathsep(ch) then kind = CharType.PathSep
          elseif is_sep(ch)     then kind = CharType.OtherSep
          elseif ch == B'.'     then kind = CharType.Dot
          else                       kind = CharType.Other
          end

          if last_kind == CharType.PathSep then
            coefficients[i] = 0.9
          elseif last_kind == CharType.OtherSep then
            coefficients[i] = 0.8
          elseif last_kind == CharType.Lower and is_upper(ch) then
            coefficients[i] = 0.75
          elseif last_kind == CharType.Dot then
            coefficients[i] = 0.7
          end
        end
      end
    end)(),
  },

  __tostring = function(self)
    return string.format("Matrix:\n\n%s", self._scoreboard)
  end,
}

local TEST_CASES = {
  { "ab/cd/ef", "ace", },
  { "ab/cd/ef", "bdf", },
  { "ab/cd/ef", "bdef", },
  { "ab/cd/ef", "abcdef", },
  { "ab/cd/ef", "ab/cd/ef", },
  { "ab/cd/ef", "ac", },
  { "ab/cd/ef", "ce", },
  { "ab/cd/ef", "ceg", },
  { "ab/cd/ef", "", },
  { "", "", },
}

local function main()
  local session = setmetatable({}, MatchSession)
  local r

  local upper = 1000000
  if DEBUG then
    upper = 1
  end

  for idx, test_case in ipairs(TEST_CASES) do
    local score = session:get_match_score(test_case[1], test_case[2])
    dprintf("%f", score)
  end

  for i = 1, upper do
    -- dprintf("---")
    -- r = session:get_match_score("ab/cd/ef", "ace")
    --
    -- dprintf("---")
    -- r = session:get_match_score("ab/cd/ef", "bdf")
    --
    dprintf("---")
    r = session:get_match_score("ab/cd/ef", "bdff")

    dprintf("---")
    r = session:get_match_score("ab/cd/ef", "bgff")


    dprintf("---")
    r = session:get_match_score("foobarsdfsd", "obrrradsfsadr")
  end

end

main()
