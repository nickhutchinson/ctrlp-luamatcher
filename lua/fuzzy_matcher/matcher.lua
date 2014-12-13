require 'fuzzy_matcher.internal.strict'
local ffi = require 'ffi'

local Matrix = require 'fuzzy_matcher.internal.matrix'
local Vector = require 'fuzzy_matcher.internal.vector'
local Sort = require 'fuzzy_matcher.internal.sort'

local function printf(...)
  print(string.format(...))
end

local DEBUG = false
local function NOOP() end

local dprintf = NOOP
if DEBUG then dprintf = printf end

local DEBUG_BOUNDS_CHECKING = false
--------------------------------------------------------------------------------
local value_type = ffi.typeof'double'

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

  local equivalence_table = Vector('char')(256)
  for i = 0, 255 do
    equivalence_table[i] = to_lower(i)
  end

  return function(ch1, ch2)
    assert(not DEBUG_BOUNDS_CHECKING or 0 <= ch1 and ch1 <= 255)
    assert(not DEBUG_BOUNDS_CHECKING or 0 <= ch2 and ch2 <= 255)
    return equivalence_table[ch1] == equivalence_table[ch2]
  end
end)()

-- Coefficients inspired by the mighty Command-T
-- (https://github.com/wincent/Command-T) and lightly tweaked.
local match_coefficient_for_idx = (function()
  local CharType = {
    Lower = 1, PathSep = 2, OtherSep = 3, Dot = 4, Other = 0, }

  local function classify(ch)
    if     is_lower(ch)   then return CharType.Lower
    elseif is_pathsep(ch) then return CharType.PathSep
    elseif is_sep(ch)     then return CharType.OtherSep
    elseif ch == B'.'     then return CharType.Dot
    else                       return CharType.Other
    end
  end

  return function(str, idx)
    if idx == 1 then return 0.85 end

    local ch = string.byte(str, idx - 1)
    local last_kind = classify(ch)

    if last_kind == CharType.PathSep then
      return 0.85
    elseif last_kind == CharType.OtherSep then
      return 0.8
    elseif last_kind == CharType.Lower and is_upper(string.byte(str, idx)) then
      return 0.75
    elseif last_kind == CharType.Dot then
      return 0.7
    else
      return 0.0
    end
  end
end)()

local function is_subsequence_of(needle, haystack)
  local m = 1
  local n = 1

  while m <= #needle and n <= #haystack do
    if is_same_letter(string.byte(needle, m), string.byte(haystack, n)) then
      m = m + 1
    end
    n = n + 1
  end
  return m == #needle + 1
end

local MatchSession = {
  __index = {
    -- get_match_score()
    -- Calculates the score if |needle| is to match the candidate string
    -- |haystack|.
    --
    -- This is a Longest Common Subsequence-type problem, which we solve using
    -- dynamic programming. See: http://en.wikipedia.org/wiki/Longest_common_subsequence_problem
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
      if #needle == 0 then return 1.0 end
      if not is_subsequence_of(needle, haystack) then return 0.0 end

      dprintf('haystack: %s, needle: %s', haystack, needle)
      self:_prepare_for_match(haystack, needle)

      local m, n = #needle + 1, #haystack + 1
      local normalized_char_score = (1.0 / (m-1) + 1.0 / (n-1)) / 2

      -- Remember folks -- m/i, n/j are the needle and haystack
      -- lengths/indices respectively.

      -- m x n matrix; follows construction detailed in the Wiki article.
      local sb = self._scoreboard

      -- match_offsets_prev tells us where the (i-1)'th needle character
      -- matched in the haystack. Specifically, match_offsets_prev[j] describes
      -- the rightmost position in the range [0, j] where we successfully
      -- matched.
      --
      -- match_offsets_prev is read from only; we populate match_offsets in the
      -- inner loop, and swap this buffer with match_offsets_prev at the end of
      -- the outer loop.
      local match_offsets, match_offsets_prev =
          self._match_offsets, self._match_offsets_prev

      local j_start = 0

      -- Outer loop: needle
      for i = 1, sb.m - 1 do
        -- Inner loop: haystack
        for j = j_start + 1, sb.n - 1 do
          local ch_i, ch_j = string.byte(needle, i), string.byte(haystack, j)

          if not is_same_letter(ch_i, ch_j) then
            dprintf("No match<%d, %d = %c, %c>", i, j, ch_i, ch_j)
            match_offsets[j] = match_offsets[j-1]
            sb:set(i, j, math.max(sb:get(i, j-1), sb:get(i-1, j)))
          else
            local c = match_coefficient_for_idx(haystack, j)
            if c == 0 then
              local distance = j - match_offsets_prev[j-1]
              assert(distance > 0)
              c = 0.75 / distance
              dprintf("Match<%d, %d = %c/%c, coef=%f, dist=%d>",
                      i, j, ch_i, ch_j, c, distance)
            else
              dprintf("Match<%d, %d = %c/%c, coef=%f, dist=n/a>",
                      i, j, ch_i, ch_j, c)
            end

            local cuml_score = sb:get(i-1, j-1) + normalized_char_score * c
            sb:set(i, j, cuml_score)

            if cuml_score >= sb:get(i, match_offsets[j-1]) then
              match_offsets[j] = j
            else
              match_offsets[j] = match_offsets[j-1]
            end

            if match_offsets[j-1] == 0 then
              j_start = j
            end
          end
        end

        local row_had_match = (0 ~= match_offsets[sb.n - 1])
        assert(row_had_match)

        -- swap the match_offsets vectors.
        match_offsets_prev, match_offsets = match_offsets, match_offsets_prev

        -- we need not zero the entire vector; the inner loop runs from
        -- j_start+1 to sb.n-1. For each j, we might read match_offsets[j-1]
        -- and we always write match_offsets[j].
        match_offsets[j_start] = 0
      end

      return sb:get(sb.m-1, sb.n-1)
    end,

    -- #_prepare_for_match()#
    -- Resets the internal state before a run; ensures the match vectors, as
    -- well as the scoreboard matrix are allocated.
    -- Args:
    --   haystack {string}:
    --   needle {string}:
    _prepare_for_match = function(self, haystack, needle)
      local m, n = #needle + 1, #haystack + 1
      self:_prepare_vector('_match_offsets', n)
      self:_prepare_vector('_match_offsets_prev', n)
      self:_prepare_matrix('_scoreboard', m, n)
    end,

    _prepare_matrix = function(self, name, m, n)
      local mat = self[name]
      if not mat or mat.capacity < m * n then
        mat = Matrix(value_type)(m, n)
        self[name] = mat
      else
        mat:clear()
        mat:reshape(m, n)
      end
    end,

    _prepare_vector = function(self, name, n)
      local vec = self[name]
      if not vec or vec.capacity < n then
        vec = Vector(value_type)(n)
        self[name] = vec
      end
      vec.length = n
    end,
  },

  __tostring = function(self)
    return string.format('Matrix:\n\n%s', self._scoreboard)
  end,
}

return MatchSession

