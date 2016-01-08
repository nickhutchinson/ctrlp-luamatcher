local Matcher = require 'fuzzy_matcher.matcher'

local candidate1 = "Cellar/graphviz/2.38.0/share/graphviz/doc/pdf/tred.1.pdf"
local candidate2 = "Cellar/boost/1.56.0/include/boost/shared_ptr.hpp"

local query = "sharedptr"

local matcher = Matcher()
matcher:set_debug_logging_enabled(true)

local score2 = matcher:match(query, candidate1)
local score3 = matcher:match(query, candidate2)

print(score2, score3)
