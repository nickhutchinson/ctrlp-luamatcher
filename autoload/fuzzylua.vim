let s:path = expand('<sfile>:p:h')

lua <<EOF
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
EOF

function! fuzzylua#Hello()
    echom "Hello goodbye"
    lua <<EOF
    local inspect = require"inspect"
    local fm = require"fuzzy_matcher.matcher"
    print(inspect(fm))
EOF
endfunction
