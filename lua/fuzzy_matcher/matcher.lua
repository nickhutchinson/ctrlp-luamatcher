local ffi = require 'ffi'

require 'fuzzy_matcher.internal.strict'
local Vector = require 'fuzzy_matcher.internal.vector'

local DEBUG = false

ffi.cdef[[
  float roundf(float x);
  float nextafterf(float x, float y);
]]

local NAN = 0/0

local function printf(...)
  io.write(string.format(...))
end

local function NOOP() end

local DLOG = NOOP
if DEBUG then DLOG = printf end

local SEPARATOR, LOWERCASE, UPPERCASE = 1, 2, 3

-- Precomputing this table makes us 10% faster.
local kCharTypeLUT = (function()
  -- Converts character `ch` to its ascii value.
  local function B(ch) return string.byte(ch, 1, 1) end

  local ret = Vector('int8_t', 256)
  for ch = 0, 255 do
    if B'A' <= ch and ch <= B'Z' then
      ret[ch] = UPPERCASE
    elseif B'a' <= ch and ch <= B'z' then
      ret[ch] = LOWERCASE
    elseif ch == B'/' or ch == B'\\' or ch == B' ' or ch == B'_' or ch == B'-' then
      ret[ch] = SEPARATOR
    else
      ret[ch] = 0
    end
  end
  return ret
end)()

local function is_upper(ch) return kCharTypeLUT[ch] == UPPERCASE end
local function is_lower(ch) return kCharTypeLUT[ch] == LOWERCASE end
local function is_separator(ch) return kCharTypeLUT[ch] == SEPARATOR end
local function to_lower(ch)
  if is_upper(ch) then return ch + 32 else return ch end
end

local function is_subsequence_of(query, candidate)
  local m = 1
  local n = 1

  while m <= #query and n <= #candidate do
    local i_ch = string.byte(query, m)
    local j_ch = string.byte(candidate, n)
    if i_ch == j_ch or to_lower(i_ch) == to_lower(j_ch) then
      m = m + 1
    end
    n = n + 1
  end
  return m == #query + 1
end

local Matcher = setmetatable(
  {
    __index = {
      __init = function(self)
        self._scoreboard = Vector('float', 8 * 64)
        self._traceback = Vector('int', 8)
        self._match_offsets = Vector('int', 64)
        self._match_offsets_prev = Vector('int', 64)
        self._debug_logging_enabled = false
        return self
      end,

      set_debug_logging_enabled = function(self, val)
        self._debug_logging_enabled = val
      end,

      debug_logging_enabled = function(self)
        return self._debug_logging_enabled
      end,

      -- :param query: the query string
      -- :param candidate: the candidate string
      -- :return: tuple of (match_score, trace_buffer)
      match = function(self, query, candidate)
        -- Algorithm is based on:
        -- - Needleman-Wunsch global sequence alignment algorithm:
        -- <https://en.wikipedia.org/wiki/Needleman–Wunsch_algorithm>
        -- - Cmd-T, the fuzzy finder plug-in for Vim:
        -- <https://github.com/wincent/command-t/blob/master/ruby/command-t/match.c>
        --
        -- ``X``: The m x n scoreboard matrix, filled in row-by-row. First row
        -- and first column of X are all zeros, to remove the need for boundary
        -- checks when accessing the matrix. (We are assured that X(i - 1, j - 1)
        -- is valid, but need to subtract 1 when indexing into ``candidate`` or
        -- ``query``.)
        --
        -- ``Y_1``: Used to track the position of the last match, so we can
        -- calculate the distance of the gap between matches. Concretely,
        -- Y_1[j] is the rightmost position in the range [0, j] where we last
        -- successfully matched on the previous row. ``Y_1`` is only read from
        -- we fill in ``Y`` as we go, which then becomes ``Y_1`` on the next
        -- row.
        --
        -- ``jStart``: where we start searching the candidate
        if #query == 0 then
          return math.huge, nil
        elseif not is_subsequence_of(query, candidate) then
          return 0.0, nil
        end

        local m, n = #query + 1, #candidate + 1
        Vector.reset(self._scoreboard, m * n)
        Vector.reset(self._traceback, #query)
        Vector.reset(self._match_offsets, n)
        Vector.reset(self._match_offsets_prev, n)

        local X = self._scoreboard
        local Y, Y_1 = self._match_offsets, self._match_offsets_prev
        local Z = self._traceback

        -- Fill the scoreboard
        local j_start = 0
        for i = 1, m - 1 do
          Y, Y_1 = Y_1, Y
          Y[j_start] = 0
          for j = j_start + 1, n - 1 do
            local i_ch = string.byte(query, i)
            local j_ch = string.byte(candidate, j)
            local j_ch_1 = j > 1 and string.byte(candidate, j - 1) or 0

            if i_ch == j_ch or to_lower(i_ch) == to_lower(j_ch) then
              -- Either:
              -- - jCh is "significant" and gets a large, fixed score.
              -- - there are no special characters behind jCh, and score
              --   decays sharply as we get further from previous match.
              local c
              if j == 1 then
                c = 0.95
              elseif is_separator(j_ch_1) or
                  is_upper(j_ch) and is_lower(j_ch_1) then
                c = 0.9
              else
                c = 0.6 * math.pow(j - Y_1[j - 1], -2.0)
              end

              local score = X[(i - 1) * n + (j - 1)] + c
              local EPSILON = 1e-4
              if math.abs(score - X[i * n + (j - 1)]) <= EPSILON then
                -- Break ties using nextafterf(). We get more sensible
                -- tracebacks in cases where a query character matches multiple
                -- locations in the candidate equally well.
                -- For example, we want to match 'b' against the 'B' at index 7
                -- here:
                --       B a B a B a B a b
                --     b 1 2 3 4 5 6 7 8 9
                X[i * n + j] = ffi.C.nextafterf(X[i * n + (j - 1)], math.huge)
              else
                X[i * n + j] = math.max(score, X[i * n + (j - 1)])
              end

              Y[j] = j
              if Y[j - 1] == 0 then j_start = j end

              DLOG("+ %c, %c; c(%d, %d)=%f\n", i_ch, j_ch, i, j, c)

            else
              X[i * n + j] = X[i * n + (j - 1)]
              Y[j] = Y[j - 1]
              DLOG("- %c, %c; X(%d, %d)=%f\n", i_ch, j_ch, i, j, X[i * n + j])
            end
          end
        end

        -- Compute the traceback: walk back from the last cell of the matrix to
        -- determine which characters of the candidate string are matched by
        -- the query.
        local j = n - 1
        for i = m - 1, 1, -1 do
          while j > 0 do
            if X[i * n + (j - 1)] < X[i * n + j] then
              Z[i - 1] = j - 1
              j = j - 1
              break
            else
              j = j - 1
            end
          end
        end

        -- Normalize the score to account for the length of the query.
        local match_score = X[(m - 1) * n + (n - 1)] / (m - 1)

        -- roundf to 2dp so we get a sort order that's more resilient to small
        -- changes in the match score.
        match_score = ffi.C.roundf(match_score * 100.0) / 100.0

        local median = X[#X/2]

        if self:debug_logging_enabled() then
          printf('---\n')
          printf('query=%s, candidate=%s\n', query, candidate)
          printf('Normalized match_score=%f\n', match_score)


          --
          -- local n = #query
          -- local mean = 0.0
          -- local M2 = 0.0
          --
          -- for i = 0, n - 1 do
          --   local x = self._traceback[i] / #candidate
          --   local delta = x - mean
          --   mean = mean + delta/(i+1)
          --   M2 = M2 + delta * (x - mean)
          -- end
          --
          -- local variance
          -- if n < 2 then
          --   variance = 0
          -- else
          --   variance = M2 / n
          -- end
          --
          -- printf("normalized mean=%f, stddev=%f\n", mean, math.sqrt(variance))
          printf("\ntraceback:\n")
          self:_dump_trace(query, candidate)
          printf("\nscoreboard:\n")
          self:_dumpMatrix(query, candidate)
          printf("---\n")
        end

        return match_score, self._traceback
      end,

      _dump_trace = function(self, query, candidate)
        local Z = self._traceback
        assert(#query <= #Z)
        printf("%s\n", candidate)
        local j = 0
        for i = 0, #candidate - 1 do
          if j < #query and i == Z[j] then
            printf("%c", string.byte(candidate, i + 1))
            j = j + 1
          else
            printf("-")
          end
        end
        printf("\n")
      end,

      _dumpMatrix = function(self, query, candidate)
        local m = #query + 1
        local n = #candidate + 1
        local X = self._scoreboard

        -- Header row
        printf("     ")
        for j = 1, n - 1 do
          printf("'%c'  ", string.byte(candidate, j))
        end
        printf("\n")

        for i = 1, m - 1 do
          printf("'%c'  ", string.byte(query, i))
          for j = 1, n - 1 do
            printf(" %.2f", X[i * n + j])
          end
          printf("\n")
        end
      end,
    }
  },
  {
    __call = function(cls, ...) return setmetatable({}, cls):__init(...) end,
  }
)

return Matcher
