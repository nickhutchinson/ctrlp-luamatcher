local Matcher = require 'fuzzy_matcher.matcher'

local TEST_CASES = {
  { 'ace', 'ab/cd/ef', },
  { 'bdf', 'ab/cd/ef', },
  { 'bdef', 'ab/cd/ef', },
  { 'abcdef', 'ab/cd/ef', },
  { 'ab/cd/ef', 'ab/cd/ef', },
  { 'ac', 'ab/cd/ef', },
  { 'ce', 'ab/cd/ef', },
  { 'ceg', 'ab/cd/ef', },
  { '', 'ab/cd/ef', },
  { '', '', },
}

local DEBUG = false

local function dprintf(...)
  print(string.format(...))
end

local function main()
  local matcher = Matcher()
  local r

  local bench_limit = 1000000
  if DEBUG then
    bench_limit = 1
  end

  for idx, test_case in ipairs(TEST_CASES) do
    local score = matcher:match(test_case[1], test_case[2])
    dprintf('%f', score)
  end

  for i = 1, bench_limit do
    r = matcher:match('ace', 'ab/cd/ef')
    r = matcher:match('bdf', 'ab/cd/ef')
    r = matcher:match('bdff', 'ab/cd/ef')
    r = matcher:match('bgff', 'ab/cd/ef')
    r = matcher:match('obrrradsfsadr', 'foobarsdfsd')
  end

end

main()
