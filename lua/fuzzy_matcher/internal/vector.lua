local ffi = require "ffi"

local BOUNDS_CHECKING = false

ffi.cdef[[
void* calloc(size_t num, size_t size);
void* realloc(void *ptr, size_t size);
void free(void* ptr);
]]

local cdecl_string = [[ struct {
  static const int ELEM_SIZE = $;
  $* data;
  int size;
  int capacity;
}]]

-- Converts the given ctype to an opaque identifier that can be used as a table
-- key.
local function typeid(ctype) return tonumber(ffi.typeof(ctype)) end

local g_vector_typeid_by_value_typeid = {}

local mt = {
  __new = function(cls, size)
    return ffi.new(cls,
                   ffi.C.calloc(size, cls.ELEM_SIZE),
                   size,
                   size)
  end,

  __gc = function(self)
    ffi.C.free(self.data)
  end,

  __len = function(self) return self.size end,

  __index = (function()
    if BOUNDS_CHECKING then
      return function(self, n)
        assert(0 <= n and n < self.size, "Index out of bounds")
        return self.data[n]
      end
    else
      return function(self, n) return self.data[n] end
    end
  end)(),

  __newindex = (function()
    if BOUNDS_CHECKING then
      return function(self, n, val)
        assert(0 <= n and n < self.size, "Index out of bounds")
        self.data[n] = val
      end
    else
      return function(self, n, val)
        self.data[n] = val
      end
    end
  end)(),

  __tostring = function(self)
    local line = {}
    for i = 0, #size - 1 do
      table.insert(line, string.format("%8.3f", self[i]))
    end
    return table.concat(line)
  end,
}

local Vector
Vector = setmetatable({
  clear = function(vec)
    ffi.fill(vec.data, vec.ELEM_SIZE * #vec)
  end,

  reset = function(vec, newSize)
    if newSize > vec.capacity then
      vec.data = ffi.C.realloc(vec.data, newSize * vec.ELEM_SIZE)
      vec.capacity = newSize
    end
    vec.size = newSize
    Vector.clear(vec)
  end,
},
{
  -- Constructor.
  __call = function(cls, value_type, ...)
    local value_typeid = typeid(value_type)
    local ctype = g_vector_typeid_by_value_typeid[value_typeid]
    if ctype == nil then
      ctype = ffi.typeof(cdecl_string, ffi.sizeof(value_type),
        ffi.typeof(value_type))
      ctype = ffi.metatype(ctype, mt)
      g_vector_typeid_by_value_typeid[value_typeid] = ctype
    end
    return ctype(...)
  end,
})

return Vector
