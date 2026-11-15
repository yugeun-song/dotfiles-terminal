if not jit or not arg then
  return
end

local ffi = require("ffi")
local bit = require("bit")

local function interactive()
  local first, index, forced, quiet = 0, nil, false, arg[0] ~= nil
  while arg[first - 1] ~= nil do
    first = first - 1
  end
  index = first + 1
  while index < 0 do
    local flag = arg[index]:sub(1, 2)
    forced = forced or flag == "-i"
    quiet = quiet or flag == "-e" or flag == "-v" or flag == "-b"
    index = index + ((flag == "-e" or flag == "-l" or flag == "-j") and #arg[index] == 2 and 2 or 1)
  end
  if forced or quiet then
    return forced
  end
  return pcall(ffi.cdef, "int isatty(int);") and ffi.C.isatty(0) ~= 0
end

if not interactive() then
  return
end

local U64, I64 = ffi.typeof("uint64_t"), ffi.typeof("int64_t")
local Int = ffi.typeof("struct { int64_t value; uint8_t kind; }")
local DIGITS = "0123456789ABCDEF"
local BASES = { bin = { 2, "0b", 1 }, oct = { 8, "0o", 3 }, dec = { 10, "" }, hex = { 16, "0x", 4 } }
local FLOATS = { f32 = 4, f64 = 8 }
local NAMES = { "bin", "oct", "dec", "hex" }
local KINDS, KNOWN = {}, {}
for _, bits in ipairs({ 8, 16, 32, 64 }) do
  for _, sign in ipairs({ "u", "s" }) do
    local kind = { name = sign .. bits, bits = bits, signed = sign == "s", index = #KINDS + 1 }
    KINDS[kind.index], KINDS[kind.name] = kind, kind
    NAMES[#NAMES + 1] = kind.name
    KNOWN[(kind.signed and "" or "u") .. "int" .. bits .. "_t"] = kind.name
  end
end
NAMES[#NAMES + 1], NAMES[#NAMES + 2] = "f32", "f64"
for _, name in ipairs(NAMES) do
  KNOWN[name] = name
end
for name, kind in pairs({
  size_t = "u64",
  ssize_t = "s64",
  intptr_t = "s64",
  uintptr_t = "u64",
  ptrdiff_t = "s64",
  intmax_t = "s64",
  uintmax_t = "u64",
  uint = "u32",
  ulong = "u64",
  ushort = "u16",
  float = "f32",
  double = "f64",
}) do
  KNOWN[name] = kind
end
local WORDS = { signed = 1, unsigned = 1, char = 1, short = 1, int = 1, long = 2 }
local APART = { { "signed", "unsigned" }, { "char", "short", "long" }, { "char", "int" } }
local SIZES = { char = 8, short = 16, long = 64 }

local UNITS = { "byte", "kb", "mb", "gb", "tb" }
local SPELLED = { b = "byte", byte = "byte", bytes = "byte" }
for unit, words in pairs({
  kb = { "kilo", "kibi" },
  mb = { "mega", "mebi" },
  gb = { "giga", "gibi" },
  tb = { "tera", "tebi" },
}) do
  SPELLED[unit], SPELLED[unit:sub(1, 1) .. "ib"] = unit, unit
  for _, word in ipairs(words) do
    SPELLED[word .. "byte"], SPELLED[word .. "bytes"] = unit, unit
  end
end

local helpers, units, raw = {}, {}, print
local shown, hooked, noted

local function fail(message, ...)
  error(message:format(...), 0)
end

local function decode(text, at)
  local lead = text:byte(at)
  local size = lead < 0x80 and 1 or lead < 0xC2 and 0 or lead < 0xE0 and 2 or lead < 0xF0 and 3 or lead < 0xF5 and 4
  if not size or size == 0 or at + size - 1 > #text then
    return nil
  end
  local point = size == 1 and lead or bit.band(lead, bit.rshift(0xFF, size + 1))
  for offset = 1, size - 1 do
    local byte = text:byte(at + offset)
    if bit.band(byte, 0xC0) ~= 0x80 then
      return nil
    end
    point = point * 64 + bit.band(byte, 0x3F)
  end
  local lowest = ({ 0, 0x80, 0x800, 0x10000 })[size]
  if point < lowest or point > 0x10FFFF or (point >= 0xD800 and point <= 0xDFFF) then
    return nil
  end
  return point, at + size
end

local function quote(text)
  local parts, at, length = {}, 1, 0
  while at <= #text do
    local point, after = decode(text, at)
    local piece = point and text:sub(at, after - 1)
    if not point or point < 0x20 or point == 0x7F then
      piece, after = ("\\%d"):format(text:byte(at)), at + 1
    elseif piece == '"' or piece == "\\" then
      piece = "\\" .. piece
    end
    if length + #piece > 74 then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1], at, length = piece, after, length + #piece
  end
  return '"' .. table.concat(parts) .. '"'
end

local function describe(value)
  if type(value) == "string" then
    return quote(value)
  end
  local ok, text = pcall(tostring, value)
  if not ok or type(text) ~= "string" then
    return "a value that cannot be shown"
  end
  text = text:gsub(": 0x%x+$", "")
  return #text > 80 and text:sub(1, 77) .. "..." or text
end

local function typed(value)
  return type(value) == "cdata" and ffi.istype(Int, value)
end

local function boxed(value)
  return type(value) == "cdata" and (ffi.istype(U64, value) or ffi.istype(I64, value))
end

local function real(value)
  return type(value) == "number" and value % 1 ~= 0
end

local function numeric(value)
  return typed(value) or boxed(value) or type(value) == "number"
end

local function wrap(kind, value)
  if kind.bits == 64 then
    return value
  end
  local low = bit.band(value, bit.lshift(I64(1), kind.bits) - 1)
  if kind.signed and low >= bit.lshift(I64(1), kind.bits - 1) then
    low = low - bit.lshift(I64(1), kind.bits)
  end
  return low
end

local function make(kind, value)
  return Int(wrap(kind, value), kind.index)
end

local function promote(kind)
  return kind.bits < 32 and KINDS.s32 or kind
end

local function common(left, right)
  left, right = promote(left), promote(right)
  if left.bits ~= right.bits then
    return left.bits > right.bits and left or right
  end
  return left.signed and right or left
end

local function low64(value)
  local low = ffi.cast(U64, math.fmod(math.abs(value) - math.abs(value) % 1, 2 ^ 64))
  return ffi.cast(I64, value < 0 and -low or low)
end

local function operand(value)
  if typed(value) then
    return value.value, KINDS[value.kind]
  elseif boxed(value) then
    return ffi.cast(I64, value), ffi.istype(U64, value) and KINDS.u64 or KINDS.s64
  elseif type(value) ~= "number" or value % 1 ~= 0 then
    fail("attempt to perform integer arithmetic on %s", describe(value))
  end
  local size = math.abs(value)
  if size >= 2 ^ 64 then
    fail("%.0f is wider than 64 bits, so it has no C type; convert it with u64 or another type", value)
  end
  return low64(value), size < 2 ^ 31 and KINDS.s32 or size < 2 ^ 63 and KINDS.s64 or KINDS.u64
end

local function double(value)
  if type(value) == "number" then
    return value
  end
  local number, kind = operand(value)
  if kind.name ~= "u64" then
    return tonumber(number)
  end
  number = ffi.cast(U64, number)
  return tonumber(bit.rshift(number, 32)) * 2 ^ 32 + tonumber(bit.band(number, U64(0xFFFFFFFF)))
end

local function single(value)
  local number, kind = operand(value)
  local size = ffi.cast(U64, (kind.name ~= "u64" and number < 0) and -number or number)
  if size < U64(2 ^ 53) then
    return tonumber(ffi.cast("float", double(value)))
  end
  local length, rest = 0, size
  while rest ~= 0 do
    length, rest = length + 1, bit.rshift(rest, 1)
  end
  local shift = length - 24
  local quotient = bit.rshift(size, shift)
  rest = bit.lshift(size - bit.lshift(quotient, shift), 1) + bit.band(quotient, 1)
  if rest > bit.lshift(U64(1), shift) then
    quotient = quotient + 1
  end
  return tonumber(quotient) * 2 ^ shift * ((kind.name ~= "u64" and number < 0) and -1 or 1)
end

local function pair(left, right)
  local x, a = operand(left)
  local y, b = operand(right)
  local kind = common(a, b)
  return wrap(kind, x), wrap(kind, y), kind
end

local function unsigned(kind, x, y)
  if kind.name == "u64" then
    return ffi.cast(U64, x), ffi.cast(U64, y)
  end
  return x, y
end

local function arithmetic(float, whole)
  return function(left, right)
    if real(left) or real(right) then
      return float(double(left), double(right))
    end
    local x, y, kind = pair(left, right)
    return make(kind, ffi.cast(I64, whole(x, y, kind)))
  end
end

local function divide(operation)
  return function(x, y, kind)
    if y == 0 then
      fail("attempt to divide by zero")
    end
    x, y = unsigned(kind, x, y)
    return operation(x, y)
  end
end

local function compare(test, strict)
  return function(left, right)
    if not strict and not (numeric(left) and numeric(right)) then
      return false
    end
    if real(left) or real(right) then
      return test(double(left), double(right))
    end
    local x, y, kind = pair(left, right)
    return test(unsigned(kind, x, y))
  end
end

ffi.metatype(Int, {
  __add = arithmetic(function(x, y)
    return x + y
  end, function(x, y)
    return x + y
  end),
  __sub = arithmetic(function(x, y)
    return x - y
  end, function(x, y)
    return x - y
  end),
  __mul = arithmetic(function(x, y)
    return x * y
  end, function(x, y)
    return x * y
  end),
  __div = arithmetic(
    function(x, y)
      return x / y
    end,
    divide(function(x, y)
      return x / y
    end)
  ),
  __mod = arithmetic(
    math.fmod,
    divide(function(x, y)
      return x % y
    end)
  ),
  __unm = function(value)
    return make(promote(KINDS[value.kind]), -value.value)
  end,
  __eq = compare(function(x, y)
    return x == y
  end),
  __lt = compare(function(x, y)
    return x < y
  end, true),
  __le = compare(function(x, y)
    return x <= y
  end, true),
  __tostring = function(value)
    local kind = KINDS[value.kind]
    return (tostring(kind.name == "u64" and ffi.cast(U64, value.value) or value.value):gsub("U?LL$", ""))
  end,
  __concat = function(left, right)
    return tostring(left) .. tostring(right)
  end,
  __index = function(value, key)
    if key == "type" then
      return KINDS[value.kind].name
    end
  end,
})

local function narrow(value, kind)
  return kind.bits == 64 and value or tonumber(bit.band(value, U64(0xFFFFFFFF)))
end

local function count(value, kind)
  return bit.band(tonumber((operand(value))), kind.bits - 1)
end

local function shift(native, view)
  return function(value, places)
    local number, kind = operand(value)
    kind = promote(kind)
    return make(kind, ffi.cast(I64, native(view(wrap(kind, number), kind), count(places, kind))))
  end
end

local function pattern(value, kind)
  return kind.bits == 64 and value or bit.band(value, U64(0xFFFFFFFF))
end

local function extended(value, kind)
  return kind.bits == 64 and value or wrap(KINDS.s32, value)
end

local function logic(native)
  return function(first, ...)
    local result = first
    for index = 1, select("#", ...) do
      local x, y, kind = pair(result, (select(index, ...)))
      result = make(kind, native(x, y))
    end
    return result
  end
end

local TYPED = {
  band = logic(bit.band),
  bor = logic(bit.bor),
  bxor = logic(bit.bxor),
  bnot = function(value)
    local number, kind = operand(value)
    return make(promote(kind), bit.bnot(number))
  end,
  lshift = shift(bit.lshift, pattern),
  rshift = shift(bit.rshift, pattern),
  arshift = shift(bit.arshift, extended),
  rol = shift(bit.rol, narrow),
  ror = shift(bit.ror, narrow),
  bswap = function(value)
    local number, kind = operand(value)
    kind = promote(kind)
    return make(kind, ffi.cast(I64, bit.bswap(narrow(wrap(kind, number), kind))))
  end,
}

local function plain(value)
  if not typed(value) then
    return value
  end
  local kind = KINDS[value.kind]
  if kind.bits < 64 then
    return tonumber(value.value)
  end
  return kind.signed and value.value or ffi.cast(U64, value.value)
end

local function overload(native, special)
  return function(...)
    local items, mixed = { ... }, false
    for index = 1, select("#", ...) do
      mixed = mixed or typed(items[index])
      items[index] = special and items[index] or plain(items[index])
    end
    if special and mixed then
      return special(...)
    end
    return native(unpack(items, 1, select("#", ...)))
  end
end

local function inexact(name, value)
  if math.abs(value) < 2 ^ 53 or value % 1 ~= 0 or (hooked and noted) then
    return
  end
  noted = true
  local text = (math.abs(value) < 1e21 and "%.0f" or "%.17g"):format(value)
  io.stderr:write(name, ": ", text, " is past 2^53, where a number is no longer exact; ")
  io.stderr:write("write it as a 64-bit literal (0x...ULL)\n")
end

local function codepoint(name, text)
  local total, point, at = 0, nil, 1
  while at <= #text do
    local found
    found, at = decode(text, at)
    if not found then
      fail("%s expects valid UTF-8, got %s", name, describe(text))
    end
    total, point = total + 1, point or found
  end
  if total ~= 1 then
    fail("%s expects a single character, got %s (%d code points)", name, describe(text), total)
  end
  return point
end

local function number(name, value)
  if type(value) == "boolean" then
    return value and 1 or 0
  elseif type(value) == "string" then
    return codepoint(name, value)
  elseif typed(value) or boxed(value) then
    return value
  end
  local given = type(value) == "cdata" and tonumber(value) or value
  if type(given) ~= "number" then
    fail("%s expects a number, 64-bit integer, boolean, or single character, got %s", name, describe(value))
  elseif given ~= given or math.abs(given) == math.huge then
    fail("%s expects a finite number, got %s", name, tostring(given))
  end
  return given
end

local function specifiers(text)
  local counts, bits, any = {}, 32, false
  for word in text:gmatch("%S+") do
    counts[word], any = (counts[word] or 0) + 1, true
    if counts[word] > (WORDS[word] or 0) then
      return nil
    end
    bits = SIZES[word] or bits
  end
  for _, group in ipairs(APART) do
    local found = 0
    for _, word in ipairs(group) do
      found = found + (counts[word] and 1 or 0)
    end
    if found > 1 then
      return nil
    end
  end
  return any and (counts.unsigned and "u" or "s") .. bits or nil
end

local function resolve(option)
  if option ~= nil and helpers[option] then
    return helpers[option]
  elseif type(option) ~= "string" then
    return nil
  end
  local text = option:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return KNOWN[text] or specifiers(text)
end

local function one(name, sort, old, key)
  if old and old ~= key then
    fail("%s takes one %s, got %s and %s", name, sort, old, key)
  end
  return key
end

local function pick(name, ...)
  local base, kind
  for index = 1, select("#", ...) do
    local option = select(index, ...)
    local key = resolve(option)
    if BASES[key] then
      base = one(name, "base", base, key)
    elseif key then
      kind = one(name, "type", kind, key)
    else
      fail("%s expects options among %s or a C type name, got %s", name, table.concat(NAMES, ", "), describe(option))
    end
  end
  return base or name, kind
end

local function kindof(name, option)
  local key = resolve(option)
  if not key or BASES[key] then
    fail("%s expects a type among %s or a C type name, got %s", name, table.concat(NAMES, ", ", 5), describe(option))
  end
  return key
end

local function cast(name, kind, value)
  if kind == "f32" then
    return type(value) == "number" and tonumber(ffi.cast("float", value)) or single(value)
  elseif kind == "f64" then
    return double(value)
  elseif type(value) == "number" then
    inexact(name, value)
    return make(KINDS[kind], low64(value))
  end
  return make(KINDS[kind], (operand(value)))
end

local function convert(name, value, kind)
  if kind then
    return cast(name, kind, value)
  elseif typed(value) or real(value) then
    return value
  end
  local output = cast(name, boxed(value) and ffi.istype(I64, value) and "s64" or "u64", value)
  if type(value) == "number" and (value < -2 ^ 63 or value >= 2 ^ 64) then
    io.stderr:write(name, ": the value is wider than 64 bits and was cut to the low 64\n")
  end
  return output
end

local function digit(value)
  return DIGITS:sub(value + 1, value + 1)
end

local function fraction(value, radix, prefix)
  if radix == 10 or value ~= value or math.abs(value) == math.huge then
    return tostring(value)
  end
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

local function places(value)
  local digits, rest = ("%.60f"):format(math.abs(value)):match("^(%d+)%.(%d+)$")
  local kept = (rest:sub(1, 5) == "00000" and rest:sub(1, 20) or rest:sub(1, 5)):gsub("0+$", "")
  if kept == "" then
    return digits == "0" and tostring(value) or (value < 0 and "-" or "") .. digits
  end
  return (value < 0 and "-" or "") .. digits .. "." .. kept
end

local function render(value, base)
  if base == "size" then
    if typed(value) or value == 0 or math.abs(value) < 1e-20 or math.abs(value) >= 1e21 then
      return value == 0 and "0" or tostring(value)
    end
    return value % 1 == 0 and ("%.0f"):format(value) or places(value)
  end
  local radix, prefix, step = unpack(BASES[base])
  if not typed(value) then
    return fraction(value, radix, prefix)
  elseif radix == 10 then
    return tostring(value)
  end
  local kind, text = KINDS[value.kind], ""
  local low = ffi.cast(U64, value.value)
  if kind.bits < 64 then
    low = bit.band(low, bit.lshift(U64(1), kind.bits) - 1)
  end
  repeat
    text = digit(tonumber(bit.band(low, radix - 1))) .. text
    low = bit.rshift(low, step)
  until low == 0
  return prefix .. text
end

local function result(value)
  if not (typed(value) or boxed(value)) then
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
      return value
    end
  end
  local ok, text = pcall(function()
    if shown.base == "size" and type(value) == "number" and not shown.type then
      return render(value, "size")
    end
    return render(convert(shown.name, value, shown.type), shown.base)
  end)
  return ok and text or value
end

local function define(name, body)
  helpers[body] = name
  if rawget(_G, name) == nil then
    rawset(_G, name, body)
  end
end

for name in pairs(BASES) do
  define(name, function(value, ...)
    local input = number(name, value)
    local base, kind = pick(name, ...)
    local output = convert(name, input, kind)
    shown = { name = name, base = base, type = kind }
    if not hooked then
      raw(render(output, base))
    end
    return output
  end)
end

for _, name in ipairs(NAMES) do
  if not BASES[name] then
    define(name, function(...)
      if select("#", ...) ~= 1 then
        fail("%s takes one value, got %d", name, select("#", ...))
      end
      return cast(name, name, number(name, (...)))
    end)
  end
end

local function unit(option)
  if option ~= nil and units[option] then
    return units[option]
  end
  return type(option) == "string" and SPELLED[option:lower():gsub("^%s+", ""):gsub("%s+$", "")] or nil
end

local function measures(name, ...)
  local from, kind
  for index = 1, select("#", ...) do
    local option = select(index, ...)
    local key = unit(option)
    local other = not key and resolve(option)
    if key then
      from = one(name, "unit", from, key)
    elseif other and not BASES[other] then
      kind = one(name, "type", kind, other)
    else
      local names = table.concat(UNITS, ", ") .. ", " .. table.concat(NAMES, ", ", 5)
      fail("%s expects options among %s or a C type name, got %s", name, names, describe(option))
    end
  end
  return from or "byte", kind
end

local function scale(name, value, shift, kind)
  local factor = 2 ^ math.abs(shift)
  if kind then
    value = cast(name, kind, value)
  else
    value = convert(name, value)
  end
  if type(value) == "number" then
    value = value * 2 ^ shift
    return kind == "f32" and tonumber(ffi.cast("float", value)) or value
  elseif shift >= 0 then
    return value * factor
  elseif kind or (value % factor).value == 0 then
    return value / factor
  end
  return double(value) / factor
end

local function measure(name, target, value, ...)
  local input = number(name, value)
  local from, kind = measures(name, ...)
  for index, other in ipairs(UNITS) do
    from = other == from and index or from
  end
  local output = scale(name, input, 10 * (from - target), kind)
  shown = { name = name, base = "size", type = FLOATS[kind] and kind or nil }
  if not hooked then
    raw(render(output, "size"))
  end
  return output
end

for index, name in ipairs(UNITS) do
  local body = function(value, ...)
    return measure(name, index, value, ...)
  end
  units[body] = name
  if rawget(_G, name) == nil then
    rawset(_G, name, body)
  end
  for target, other in ipairs(UNITS) do
    local both = name .. "_to_" .. other
    if target ~= index and rawget(_G, both) == nil then
      rawset(_G, both, function(value, ...)
        return measure(both, target, value, name, ...)
      end)
    end
  end
end

local function sizeof(operand_)
  if typed(operand_) then
    return KINDS[operand_.kind].bits / 8
  elseif boxed(operand_) or real(operand_) then
    return 8
  elseif type(operand_) == "number" then
    return select(2, operand(operand_)).bits / 8
  end
  local kind = kindof("sizeof", operand_)
  return FLOATS[kind] or KINDS[kind].bits / 8
end

for name, body in pairs({
  cast = function(kind, value)
    return cast("cast", kindof("cast", kind), number("cast", value))
  end,
  sizeof = function(value)
    return make(KINDS.u64, I64(sizeof(value)))
  end,
}) do
  if rawget(_G, name) == nil then
    rawset(_G, name, body)
  end
end

for name, body in pairs(bit) do
  if rawget(_G, name) == nil then
    rawset(_G, name, overload(body, TYPED[name]))
  end
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
    if type(index) == "function" then
      return index(globals, key)
    end
    if index ~= nil then
      return index[key]
    end
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
    if not shown then
      return raw(...)
    end
    local total, items = select("#", ...), { ... }
    for index = 1, total do
      items[index] = result(items[index])
    end
    return raw(unpack(items, 1, total))
  end
end
