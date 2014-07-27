local ffi = require "ffi"

ffi.cdef[[
  void* calloc(size_t, size_t);
  void free(void*);
]]

-- Converts the given ctype to an opaque identifier that can be used as a table
-- key.
local function ctypeid(ctype)
  return tonumber(ffi.typeof(ctype))
end

-- Returns, for the given ctype `T`, the ctype `T*`.
local pointer_type = (function()
  -- Cache the derived pointer type; calculating it aborts a LuaJIT trace;
  -- obviously we want to minimise this.
  local typeid_to_pointer_type = {}
  return function(ctype)
    local type_id = ctypeid(ctype)
    local derived_type = typeid_to_pointer_type[type_id]
    if derived_type == nil then
      derived_type = ffi.typeof("$*", ctype)
      typeid_to_pointer_type[type_id] = derived_type
    end
    return derived_type
  end
end)()

-- Allocates a struct; tries hard not to abort a LuaJIT trace, unlike
-- `ffi.new()`.
-- Args:
--   struct_type (ctype): the ctype to allocate
--   size (number, optional): if given, allocate |size| bytes instead of
--     sizeof(|struct_type|). Useful for variable-length structs.
local function allocate_struct(struct_type, size)
  size = size or ffi.sizeof(struct_type)
  local ptr_t = pointer_type(struct_type)
  local struct_ptr = ffi.cast(ptr_t, ffi.C.calloc(1, size))
  return ffi.gc(struct_ptr[0], ffi.C.free)
end

return {
  allocate_struct = allocate_struct,
  pointer_type = pointer_type,
  ctypeid = ctypeid,
}

