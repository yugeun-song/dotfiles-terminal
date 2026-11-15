if not jit or not arg then return end

local ffi = require("ffi")
local bit = require("bit")

local function interactive()
  local first, index, forced, quiet = 0, nil, false, arg[0] ~= nil
  while arg[first - 1] ~= nil do first = first - 1 end
  index = first + 1
  while index < 0 do
    local flag = arg[index]:sub(1, 2)
    forced = forced or flag == "-i"
    quiet = quiet or flag == "-e" or flag == "-v" or flag == "-b"
    index = index + ((flag == "-e" or flag == "-l" or flag == "-j") and #arg[index] == 2 and 2 or 1)
  end
  if forced or quiet then return forced end
  return pcall(ffi.cdef, "int isatty(int);") and ffi.C.isatty(0) ~= 0
end

if not interactive() then return end

local U64, I64 = ffi.typeof("uint64_t"), ffi.typeof("int64_t")
local DIGITS = "0123456789ABCDEF"
local BASES = { bin = { 2, "0b", 1 }, oct = { 8, "0o", 3 }, dec = { 10, "" }, hex = { 16, "0x", 4 } }
local INTS, FLOATS = {}, { f32 = "float", f64 = "double" }
local NAMES = { "bin", "oct", "dec", "hex" }
for _, bits in ipairs({ 8, 16, 32, 64 }) do
  for _, sign in ipairs({ "u", "s" }) do
    INTS[sign .. bits] = { bits, sign == "s" }
    NAMES[#NAMES + 1] = sign .. bits
  end
end
NAMES[#NAMES + 1], NAMES[#NAMES + 2] = "f32", "f64"

local helpers, raw = {}, print
local shown, hooked, noted

local function fail(message, ...)
  error(message:format(...), 0)
end

local function describe(value)
  local ok, text = pcall(tostring, value)
  if type(value) == "string" then
    text = ("%q"):format(value):gsub("\\\n", "\\n")
  elseif not ok or type(text) ~= "string" then
    text = "a value that cannot be shown"
  end
  return #text > 80 and text:sub(1, 77) .. "..." or text
end

local function boxed(value)
  return type(value) == "cdata" and (ffi.istype(U64, value) or ffi.istype(I64, value))
end

local function inexact(name, value)
  if math.abs(value) < 2 ^ 53 or value % 1 ~= 0 or (hooked and noted) then return end
  noted = true
  local text = (math.abs(value) < 1e21 and "%.0f" or "%.17g"):format(value)
  io.stderr:write(name, ": ", text, " is past 2^53, where a number is no longer exact; ")
  io.stderr:write("write it as a 64-bit literal (0x...ULL)\n")
end

local function decode(text, at)
  local lead = text:byte(at)
  local size = lead < 0x80 and 1 or lead < 0xC2 and 0 or lead < 0xE0 and 2 or lead < 0xF0 and 3 or lead < 0xF5 and 4
  if not size or size == 0 or at + size - 1 > #text then return nil end
  local point = size == 1 and lead or bit.band(lead, bit.rshift(0xFF, size + 1))
  for offset = 1, size - 1 do
    local byte = text:byte(at + offset)
    if bit.band(byte, 0xC0) ~= 0x80 then return nil end
    point = point * 64 + bit.band(byte, 0x3F)
  end
  local lowest = ({ 0, 0x80, 0x800, 0x10000 })[size]
  if point < lowest or point > 0x10FFFF or (point >= 0xD800 and point <= 0xDFFF) then return nil end
  return point, at + size
end

local function codepoint(name, text)
  local count, point, at = 0, nil, 1
  while at <= #text do
    local found
    found, at = decode(text, at)
    if not found then fail("%s expects valid UTF-8, got %s", name, describe(text)) end
    count, point = count + 1, point or found
  end
  if count ~= 1 then fail("%s expects a single character, got %s (%d code points)", name, describe(text), count) end
  return point
end

local function number(name, value)
  if type(value) == "boolean" then return value and 1 or 0 end
  if type(value) == "string" then return codepoint(name, value) end
  if boxed(value) then return value end
  local plain = type(value) == "cdata" and tonumber(value) or value
  if type(plain) ~= "number" then
    fail("%s expects a number, 64-bit integer, boolean, or single character, got %s", name, describe(value))
  end
  if plain ~= plain or math.abs(plain) == math.huge then
    fail("%s expects a finite number, got %s", name, tostring(plain))
  end
  inexact(name, plain)
  return plain
end

local function one(name, kind, old, key)
  if old and old ~= key then fail("%s takes one %s, got %s and %s", name, kind, old, key) end
  return key
end

local function pick(name, ...)
  local base, kind
  for index = 1, select("#", ...) do
    local option = select(index, ...)
    local key = option ~= nil and helpers[option] or type(option) == "string" and option:lower()
    if BASES[key] then
      base = one(name, "base", base, key)
    elseif INTS[key] or FLOATS[key] then
      kind = one(name, "type", kind, key)
    else
      fail("%s expects options among %s, got %s", name, table.concat(NAMES, ", "), describe(option))
    end
  end
  return base or name, kind
end

local function fold(kind, value)
  local bits, signed = unpack(INTS[kind])
  local low
  if type(value) == "cdata" then
    low = ffi.cast(U64, value)
  else
    low = ffi.cast(U64, math.fmod(math.abs(value) - math.abs(value) % 1, 2 ^ 64))
    if value < 0 then low = -low end
  end
  if bits < 64 then low = bit.band(low, bit.lshift(U64(1), bits) - 1) end
  local wide = ffi.cast(I64, low)
  if signed and bits < 64 and low >= bit.lshift(U64(1), bits - 1) then wide = wide - bit.lshift(I64(1), bits) end
  return low, wide, signed, bits
end

local function double(value)
  if not ffi.istype(U64, value) then return tonumber(value) end
  return tonumber(bit.rshift(value, 32)) * 2 ^ 32 + tonumber(bit.band(value, U64(0xFFFFFFFF)))
end

local function cast(kind, value)
  if FLOATS[kind] then return tonumber(ffi.cast(FLOATS[kind], double(value))) end
  local low, wide, signed, bits = fold(kind, value)
  if bits < 64 and type(value) == "number" then return tonumber(wide) end
  return signed and wide or low
end

local function digit(value)
  return DIGITS:sub(value + 1, value + 1)
end

local function real(value, radix, prefix)
  if radix == 10 or value ~= value or math.abs(value) == math.huge then return tostring(value) end
  local size = math.abs(value)
  local rest = size % 1
  local whole, text = size - rest, ""
  repeat
    text = digit(whole % radix) .. text
    whole = (whole - whole % radix) / radix
  until whole == 0
  text = ((value < 0 or 1 / value < 0) and "-" or "") .. prefix .. text .. (rest > 0 and "." or "")
  while rest > 0 do
    rest = rest * radix
    text = text .. digit(math.floor(rest))
    rest = rest % 1
  end
  return text
end

local function render(name, value, base, kind)
  local radix, prefix, shift = unpack(BASES[base])
  if FLOATS[kind] then return real(cast(kind, value), radix, prefix) end
  if not kind and type(value) == "number" and value % 1 ~= 0 then return real(value, radix, prefix) end

  local suffix = type(value) == "cdata" and (ffi.istype(U64, value) and "ULL" or "LL") or ""
  if not kind and type(value) == "number" and (value < -2 ^ 63 or value >= 2 ^ 64) then
    io.stderr:write(name, ": the value is wider than 64 bits and only the low 64 are shown\n")
  end
  local low, wide, signed = fold(kind or "u64", value)
  if radix == 10 then return tostring(signed and wide or low):gsub("U?LL$", suffix) end
  local text = ""
  repeat
    text = digit(tonumber(bit.band(low, radix - 1))) .. text
    low = bit.rshift(low, shift)
  until low == 0
  return prefix .. text .. suffix
end

local function result(value)
  if not boxed(value) then
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return value end
    inexact(shown.name, value)
  end
  local ok, text = pcall(render, shown.name, value, shown.base, shown.type)
  return ok and text or value
end

local function define(name, body)
  helpers[body] = name
  if rawget(_G, name) == nil then rawset(_G, name, body) end
end

for name in pairs(BASES) do
  define(name, function(value, ...)
    local input = number(name, value)
    local base, kind = pick(name, ...)
    shown = { name = name, base = base, type = kind }
    if not hooked then raw((render(name, input, base, kind))) end
    return input
  end)
end

for _, name in ipairs(NAMES) do
  if not BASES[name] then
    define(name, function(...)
      if select("#", ...) ~= 1 then fail("%s takes one value, got %d", name, select("#", ...)) end
      return cast(name, number(name, (...)))
    end)
  end
end

for name, body in pairs(bit) do
  if rawget(_G, name) == nil then rawset(_G, name, body) end
end

hooked = pcall(function()
  local meta = getmetatable(_G) or {}
  local index, newindex = meta.__index, meta.__newindex
  local prompt = rawget(_G, "_PROMPT")

  meta.__index = function(globals, key)
    if key == "_PROMPT" then
      shown, noted = nil, false
      return prompt
    end
    if type(index) == "function" then return index(globals, key) end
    if index ~= nil then return index[key] end
  end

  meta.__newindex = function(globals, key, value)
    if key == "_PROMPT" then
      prompt = value
    elseif type(newindex) == "function" then
      newindex(globals, key, value)
    elseif newindex ~= nil then
      newindex[key] = value
    else
      rawset(globals, key, value)
    end
  end

  setmetatable(_G, meta)
  rawset(_G, "_PROMPT", nil)
end)

if hooked then
  print = function(...)
    if not shown then return raw(...) end
    local count, items = select("#", ...), { ... }
    for index = 1, count do items[index] = result(items[index]) end
    return raw(unpack(items, 1, count))
  end
end
