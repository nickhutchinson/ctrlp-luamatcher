local TEST_CASES = {
  { 'ab/cd/ef', 'ace', },
  { 'ab/cd/ef', 'bdf', },
  { 'ab/cd/ef', 'bdef', },
  { 'ab/cd/ef', 'abcdef', },
  { 'ab/cd/ef', 'ab/cd/ef', },
  { 'ab/cd/ef', 'ac', },
  { 'ab/cd/ef', 'ce', },
  { 'ab/cd/ef', 'ceg', },
  { 'ab/cd/ef', '', },
  { '', '', },
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
    dprintf('%f', score)
  end

  for i = 1, upper do
    -- dprintf('---')
    -- r = session:get_match_score('ab/cd/ef', 'ace')
    --
    -- dprintf('---')
    -- r = session:get_match_score('ab/cd/ef', 'bdf')
    --
    dprintf('---')
    r = session:get_match_score('ab/cd/ef', 'bdff')

    dprintf('---')
    r = session:get_match_score('ab/cd/ef', 'bgff')


    dprintf('---')
    r = session:get_match_score('foobarsdfsd', 'obrrradsfsadr')
  end

end

main()
