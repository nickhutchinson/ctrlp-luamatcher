local FFIUtil = require "fuzzy_matcher.support.ffi_util"
local ffi = require "ffi"
local DEBUG_BOUNDS_CHECKING = false

local cdecl_string = [[ struct {
  static const int ELEM_SIZE = $;
  int capacity;
  int length;
  $ data[0];
}]]

local ctype_by_value_typeid = {}

local function NOOP() end

local check_index = NOOP
if DEBUG_BOUNDS_CHECKING == true then
  check_index = function (self, idx)
    assert(0 <= idx and idx < self.capacity)
  end
end

local metatable = {
  __new = function(cls, capacity)
    local size = ffi.sizeof(cls) + capacity * cls.ELEM_SIZE
    local obj = FFIUtil.allocate_struct(cls, size)
    obj.capacity = capacity
    return obj
  end,

  __len = function(self)
    return self.length
  end,

  __index = function(self, idx)
    check_index(self, idx)
    return self.data[idx]
  end,

  __newindex = function(self, idx, val)
    check_index(self, idx)
    self.data[idx] = val
  end,

  __tostring = function(self)
    local line = {}
    for i = 0, self.capacity - 1 do
      table.insert(line, string.format("%8.3f", self[i]))
    end
    return table.concat(line)
  end,
}

local Vector = setmetatable({
  clear = function(self)
    ffi.fill(self.data, self.ELEM_SIZE * self.capacity)
  end,
  fill = function(self, val)
    for i=0, #self-1 do
      self.data[i] = val
    end
  end,
},
{
  __call = function(cls, value_type)
    local type_id = FFIUtil.ctypeid(value_type)
    local ctype = ctype_by_value_typeid[type_id]
    if ctype == nil then
      ctype = ffi.typeof(cdecl_string, ffi.sizeof(value_type),
        ffi.typeof(value_type))
      ctype = ffi.metatype(ctype, metatable)
      ctype_by_value_typeid[type_id] = ctype
    end
    return ctype
  end,
})

return Vector
