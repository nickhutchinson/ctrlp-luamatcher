local Matcher = require 'fuzzy_matcher.matcher'

local candidates = {
  'Cellar/boost/1.56.0/include/boost/shared_ptr.hpp',
  'Cellar/boost/1.59.0/include/boost/asio/detail/shared_ptr.hpp',
  'Cellar/boost/1.59.0/include/boost/shared_ptr.hpp',
  'Cellar/boost/1.59.0/include/boost/smart_ptr/shared_ptr.hpp',
  'Cellar/boost/1.59.0/include/boost/thread/csbl/memory/shared_ptr.hpp',
  'Cellar/graphviz/2.38.0/share/graphviz/doc/pdf/tred.1.pdf',
  'Cellar/swig/3.0.8/share/swig/3.0.8/csharp/boost_shared_ptr.i',
}

local query = "sharedptr"

local matcher = Matcher()
matcher:set_debug_logging_enabled(true)

for _, candidate in ipairs(candidates) do
  matcher:match(query, candidate)
end

