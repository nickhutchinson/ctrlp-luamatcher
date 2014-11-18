local ffi = require "ffi"
local FFIUtil = require "fuzzy_matcher.internal.ffi_util"
local DEBUG_BOUNDS_CHECKING = false

local cdecl_string = [[ struct {
  static const int ELEM_SIZE = $;
  int m, n, capacity;
  $ data[0];
}]]

local ctype_by_value_typeid = {}

local function NOOP() end

local check_index = NOOP
if DEBUG_BOUNDS_CHECKING == true then
  check_index = function(self, i, j)
    assert(0 <= i and i < self.m)
    assert(0 <= j and j < self.n)
  end
end

local metatable = {
  __new = function(cls, m, n)
    local size = m * n * cls.ELEM_SIZE + ffi.sizeof(cls)
    local matrix = FFIUtil.allocate_struct(cls, size)
    matrix.capacity, matrix.m, matrix.n = m * n, m, n
    return matrix
  end,

  __tostring = function(self)
    local lines = {}
    for i = 0, self.m - 1 do
      local line = {}
      for j = 0, self.n - 1 do
        table.insert(line, string.format("%8.3f", self(i, j)))
      end
      table.insert(lines, table.concat(line))
    end
    return table.concat(lines, "\n")
  end,

  __call = function(self, i, j)
      check_index(self, i, j)
      return self.data[i * self.n + j]
  end,

  __index = {
    get = function(self, i, j)
      check_index(self, i, j)
      return self.data[i * self.n + j]
    end,

    set = function(self, i, j, v)
      check_index(self, i, j)
      self.data[i * self.n + j] = v
    end,

    clear = function(self)
      ffi.fill(self.data, self.capacity * self.ELEM_SIZE)
    end,

    reshape = function(self, m, n)
      assert(self.capacity >= m * n)
      self.m, self.n = m, n
    end,
  },
}

local Matrix = setmetatable({}, {
  __call = function(cls, value_type)
    local type_id = FFIUtil.ctypeid(value_type)
    local ctype = ctype_by_value_typeid[type_id]

    if ctype == nil then
      ctype = ffi.typeof(cdecl_string, ffi.sizeof(value_type), value_type)
      ffi.metatype(ctype, metatable)
      ctype_by_value_typeid[type_id] = ctype
    end
    return ctype
  end,
})

return Matrix
