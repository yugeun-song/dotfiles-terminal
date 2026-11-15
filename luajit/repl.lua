if not jit or not arg then
  return
end

local ffi = require("ffi")
local bit = require("bit")

---True only for the interactive prompt: `-i`, or no script and a terminal on standard input.
---@return boolean
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
---An integer with a C type: 64 bits of value and an index into KINDS.
local Int = ffi.typeof("struct { int64_t value; uint8_t kind; }")
---A single-precision number, C's float; arithmetic on it stays in single precision.
local Single = ffi.typeof("struct { float value; }")
local DIGITS = "0123456789ABCDEF"
---Each base helper's radix, prefix and bits per digit.
local BASES = { bin = { 2, "0b", 1 }, oct = { 8, "0o", 3 }, dec = { 10, "" }, hex = { 16, "0x", 4 } }
local FLOATS = { f32 = 4, f64 = 8 }
local NAMES = { "bin", "oct", "dec", "hex" }
---KINDS: each integer type's name, width and sign, by index and by name. KNOWN: every spelling of a base or a type.
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

---The size units, each 1024 times the one before.
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
---shown: the last helper's name, base and type in this statement. hooked: whether the prompt and `print` are ours. noted: whether a note was already written.
local shown, hooked, noted

---Raises an error with a formatted message and no position.
---@param message string
---@param ... any
local function fail(message, ...)
  error(message:format(...), 0)
end

---Decodes one UTF-8 sequence, rejecting overlong forms and surrogates.
---@param text string
---@param at integer byte position
---@return integer? point
---@return integer? after position after the sequence
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

---Quotes a string for an error message, escaping bytes that are not printable UTF-8.
---@param text string
---@return string
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

---Shows a value for an error message, without the address that changes between runs.
---@param value any
---@return string
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

---Whether a value is one of ours: an integer that carries a C type.
---@param value any
---@return boolean
local function typed(value)
  return type(value) == "cdata" and ffi.istype(Int, value)
end

---Whether a value is a single-precision number of ours.
---@param value any
---@return boolean
local function floating(value)
  return type(value) == "cdata" and ffi.istype(Single, value)
end

---Whether a value is LuaJIT's own 64-bit integer (`1LL`, `1ULL`).
---@param value any
---@return boolean
local function boxed(value)
  return type(value) == "cdata" and (ffi.istype(U64, value) or ffi.istype(I64, value))
end

---Whether a value is a number with a fraction.
---@param value any
---@return boolean
local function real(value)
  return type(value) == "number" and value % 1 ~= 0
end

---Whether a value can take part in arithmetic here.
---@param value any
---@return boolean
local function numeric(value)
  return typed(value) or boxed(value) or floating(value) or type(value) == "number"
end

---Cuts a 64-bit value to a type's width and extends its sign, as a C conversion does.
---@param kind table an entry of KINDS
---@param value ffi.cdata* int64_t
---@return ffi.cdata* int64_t
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

---Builds a typed integer from a 64-bit value.
---@param kind table
---@param value ffi.cdata*
---@return ffi.cdata* Int
local function make(kind, value)
  return Int(wrap(kind, value), kind.index)
end

---C's integer promotion: a type narrower than `int` becomes `s32`.
---@param kind table
---@return table
local function promote(kind)
  return kind.bits < 32 and KINDS.s32 or kind
end

---C's usual arithmetic conversion: the wider type, and of two equally wide ones the unsigned.
---@param left table
---@param right table
---@return table
local function common(left, right)
  left, right = promote(left), promote(right)
  if left.bits ~= right.bits then
    return left.bits > right.bits and left or right
  end
  return left.signed and right or left
end

---The low 64 bits of a whole number, however large.
---@param value number
---@return ffi.cdata* int64_t
local function low64(value)
  local low = ffi.cast(U64, math.fmod(math.abs(value) - math.abs(value) % 1, 2 ^ 64))
  return ffi.cast(I64, value < 0 and -low or low)
end

---An integer operand as 64 bits and its type. A plain number is typed as a decimal C constant: `s32`, else `s64`, else `u64`.
---@param value any
---@return ffi.cdata* bits
---@return table kind
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

---A value as a double, with a `u64` converted exactly as C converts it.
---@param value any
---@return number
local function double(value)
  if type(value) == "number" then
    return value
  elseif floating(value) then
    return tonumber(value.value)
  end
  local number, kind = operand(value)
  if kind.name ~= "u64" then
    return tonumber(number)
  end
  number = ffi.cast(U64, number)
  return tonumber(bit.rshift(number, 32)) * 2 ^ 32 + tonumber(bit.band(number, U64(0xFFFFFFFF)))
end

---A typed integer rounded once to single precision, ties to even.
---@param value any
---@return number
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

---Both operands converted to their common type.
---@param left any
---@param right any
---@return ffi.cdata* x
---@return ffi.cdata* y
---@return table kind
local function pair(left, right)
  local x, a = operand(left)
  local y, b = operand(right)
  local kind = common(a, b)
  return wrap(kind, x), wrap(kind, y), kind
end

---Views two operands as unsigned when the type is `u64`, so that division and comparison follow it.
---@param kind table
---@param x ffi.cdata*
---@param y ffi.cdata*
local function unsigned(kind, x, y)
  if kind.name == "u64" then
    return ffi.cast(U64, x), ffi.cast(U64, y)
  end
  return x, y
end

---Makes a binary metamethod: floats when either side has a fraction, else C integer arithmetic in the common type.
---@param float fun(x: number, y: number): number
---@param whole fun(x: ffi.cdata*, y: ffi.cdata*, kind: table): ffi.cdata*
---@return function
---An operand of single-precision arithmetic: an integer beside a float is converted to a float first.
---@param value any
---@return number
local function narrowed(value)
  if floating(value) then
    return tonumber(value.value)
  elseif type(value) == "number" then
    return tonumber(ffi.cast("float", value))
  end
  return single(value)
end

local function arithmetic(float, whole)
  return function(left, right)
    if real(left) or real(right) then
      return float(double(left), double(right))
    elseif floating(left) or floating(right) then
      return Single(float(narrowed(left), narrowed(right)))
    end
    local x, y, kind = pair(left, right)
    return make(kind, ffi.cast(I64, whole(x, y, kind)))
  end
end

---Wraps a division so that a zero divisor is an error and `u64` divides unsigned.
---@param operation function
---@return function
local function divide(operation)
  return function(x, y, kind)
    if y == 0 then
      fail("attempt to divide by zero")
    end
    x, y = unsigned(kind, x, y)
    return operation(x, y)
  end
end

---Makes a comparison metamethod that compares in the common type, as C does.
---@param test function
---@param strict? boolean raise for a value that is not a number
---@return function
local function compare(test, strict)
  return function(left, right)
    if not strict and not (numeric(left) and numeric(right)) then
      return false
    end
    if real(left) or real(right) then
      return test(double(left), double(right))
    elseif floating(left) or floating(right) then
      return test(narrowed(left), narrowed(right))
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

---A 64-bit value as the 32-bit number `bit.*` expects, unless the type is 64 bits wide.
---@param value ffi.cdata*
---@param kind table
ffi.metatype(Single, {
  __add = arithmetic(function(x, y)
    return x + y
  end),
  __sub = arithmetic(function(x, y)
    return x - y
  end),
  __mul = arithmetic(function(x, y)
    return x * y
  end),
  __div = arithmetic(function(x, y)
    return x / y
  end),
  __unm = function(value)
    return Single(-value.value)
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
    return tostring(tonumber(value.value))
  end,
  __concat = function(left, right)
    return tostring(left) .. tostring(right)
  end,
  __index = function(_, key)
    if key == "type" then
      return "f32"
    end
  end,
})

local function narrow(value, kind)
  return kind.bits == 64 and value or tonumber(bit.band(value, U64(0xFFFFFFFF)))
end

---A shift count reduced as the x86-64 instruction reduces it: its low 5 or 6 bits.
---@param value any
---@param kind table
---@return integer
local function count(value, kind)
  return bit.band(tonumber((operand(value))), kind.bits - 1)
end

---Makes a typed shift: the result has the promoted type of the left operand.
---@param native function
---@param view function how the bits are read before shifting
---@return function
local function shift(native, view)
  return function(value, places)
    local number, kind = operand(value)
    kind = promote(kind)
    return make(kind, ffi.cast(I64, native(view(wrap(kind, number), kind), count(places, kind))))
  end
end

---The bits of a value as unsigned, for a logical shift.
---@param value ffi.cdata*
---@param kind table
local function pattern(value, kind)
  return kind.bits == 64 and value or bit.band(value, U64(0xFFFFFFFF))
end

---The bits of a value sign-extended, for an arithmetic shift.
---@param value ffi.cdata*
---@param kind table
local function extended(value, kind)
  return kind.bits == 64 and value or wrap(KINDS.s32, value)
end

---Makes a typed `band`, `bor` or `bxor` over any number of operands.
---@param native function
---@return function
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

---The `bit.*` functions for typed operands, by C's rules.
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

---A typed value as what LuaJIT itself would use: a number below 64 bits, a 64-bit integer otherwise.
---@param value any
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

---Wraps a `bit.*` function: typed operands use the typed version, others the original.
---@param native function
---@param special? function
---@return function
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

---Notes, once per statement, that a whole number past 2^53 is no longer exact.
---@param name string
---@param value number
local function inexact(name, value)
  if math.abs(value) < 2 ^ 53 or value % 1 ~= 0 or (hooked and noted) then
    return
  end
  noted = true
  local text = (math.abs(value) < 1e21 and "%.0f" or "%.17g"):format(value)
  io.stderr:write(name, ": ", text, " is past 2^53, where a number is no longer exact; ")
  io.stderr:write("write it as a 64-bit literal (0x...ULL)\n")
end

---The code point of a one-character UTF-8 string; fails for any other length.
---@param name string
---@param text string
---@return integer
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

---Turns a helper's input into a number or an integer: booleans are 1 and 0, a one-character string is its code point.
---@param name string
---@param value any
local function number(name, value)
  if type(value) == "boolean" then
    return value and 1 or 0
  elseif type(value) == "string" then
    return codepoint(name, value)
  elseif typed(value) or boxed(value) or floating(value) then
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

---Reads C type specifiers in any order (`unsigned long int`) as GCC does on x86-64.
---@param text string
---@return string? name `u8` to `s64`
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

---The base or type an option names: a helper function, one of our names, or a C type name.
---@param option any
---@return string?
local function resolve(option)
  if option ~= nil and helpers[option] then
    return helpers[option]
  elseif type(option) ~= "string" then
    return nil
  end
  local text = option:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return KNOWN[text] or specifiers(text)
end

---Keeps an option of a sort, and fails when a different one of that sort was already given.
---@param name string
---@param sort string
---@param old string?
---@param key string
---@return string
local function one(name, sort, old, key)
  if old and old ~= key then
    fail("%s takes one %s, got %s and %s", name, sort, old, key)
  end
  return key
end

---Splits the options of `bin`, `oct`, `dec` and `hex` into a base and a type.
---@param name string
---@param ... any
---@return string base
---@return string? kind
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

---The type an option names, for `cast` and `sizeof`; fails for a base or anything else.
---@param name string
---@param option any
---@return string
local function kindof(name, option)
  local key = resolve(option)
  if not key or BASES[key] then
    fail("%s expects a type among %s or a C type name, got %s", name, table.concat(NAMES, ", ", 5), describe(option))
  end
  return key
end

---Converts as the C cast `(kind)value` does: a typed integer, or a number for `f32` and `f64`.
---@param name string
---@param kind string
---@param value any
local function cast(name, kind, value)
  if floating(value) then
    value = tonumber(value.value)
  end
  if kind == "f32" then
    return Single(type(value) == "number" and value or single(value))
  elseif kind == "f64" then
    return double(value)
  elseif type(value) == "number" then
    inexact(name, value)
    return make(KINDS[kind], low64(value))
  end
  return make(KINDS[kind], (operand(value)))
end

---The value a helper returns: converted to `kind`, or with none a whole number as a `u64` and anything typed or fractional as it is.
---@param name string
---@param value any
---@param kind? string
local function convert(name, value, kind)
  if kind then
    return cast(name, kind, value)
  elseif typed(value) or real(value) or floating(value) then
    return value
  end
  local output = cast(name, boxed(value) and ffi.istype(I64, value) and "s64" or "u64", value)
  if type(value) == "number" and (value < -2 ^ 63 or value >= 2 ^ 64) then
    io.stderr:write(name, ": the value is wider than 64 bits and was cut to the low 64\n")
  end
  return output
end

---One digit, upper case.
---@param value integer
---@return string
local function digit(value)
  return DIGITS:sub(value + 1, value + 1)
end

---A number in a radix, with its exact fraction digits (`0x1.8`).
---@param value number
---@param radix integer
---@param prefix string
---@return string
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

---A number for a size: its decimal digits cut to 5 places, or to 20 when the first 5 are zeros.
---@param value number not whole
---@return string
local function places(value)
  local digits, rest = ("%.60f"):format(math.abs(value)):match("^(%d+)%.(%d+)$")
  local kept = (rest:sub(1, 5) == "00000" and rest:sub(1, 20) or rest:sub(1, 5)):gsub("0+$", "")
  if kept == "" then
    return digits == "0" and tostring(value) or (value < 0 and "-" or "") .. digits
  end
  return (value < 0 and "-" or "") .. digits .. "." .. kept
end

---The text of a value in a base. A typed integer shows the two's complement pattern of its type.
---@param value any
---@param base string `bin`, `oct`, `dec`, `hex` or `size`
---@return string
local function render(value, base)
  if floating(value) then
    value = tonumber(value.value)
  end
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

---What `print` shows for a value after a helper ran: its text in the base called last, or the value itself.
---@param value any
local function result(value)
  if not (typed(value) or boxed(value) or floating(value)) then
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

---Records a helper under its name, so that the function itself can be passed as an option, and makes it a global.
---@param name string
---@param body function
local function define(name, body)
  helpers[body] = name
  if rawget(_G, name) == nil then
    rawset(_G, name, body)
  end
end

---The unit an option names: a size helper or a spelling such as `MiB` or `megabytes`.
---@param option any
---@return string?
local function unit(option)
  if option ~= nil and units[option] then
    return units[option]
  end
  return type(option) == "string" and SPELLED[option:lower():gsub("^%s+", ""):gsub("%s+$", "")] or nil
end

---Splits the options of a size helper into the unit the value is in and a type.
---@param name string
---@param ... any
---@return string from
---@return string? kind
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

---Multiplies or divides by 1024 per step, in C's arithmetic for a typed value. Without a type among the options, a division with a remainder gives a number with a fraction.
---@param name string
---@param value any
---@param shift integer bits to shift left; negative divides
---@param kind? string
local function scale(name, value, shift, kind)
  local factor = 2 ^ math.abs(shift)
  if kind then
    value = cast(name, kind, value)
  else
    value = convert(name, value)
  end
  if floating(value) then
    return Single(tonumber(value.value) * 2 ^ shift)
  elseif type(value) == "number" then
    return value * 2 ^ shift
  elseif shift >= 0 then
    return value * factor
  elseif kind or (value % factor).value == 0 then
    return value / factor
  end
  return double(value) / factor
end

for name in pairs(BASES) do
  define(name, function(value, ...)
    local input = number(name, value)
    local from, rest, total = nil, {}, 0
    for index = 1, select("#", ...) do
      local option = select(index, ...)
      local key = unit(option)
      if key then
        from = one(name, "unit", from, key)
      else
        total = total + 1
        rest[total] = option
      end
    end
    local base, kind = pick(name, unpack(rest, 1, total))
    local output
    if from then
      for index, other in ipairs(UNITS) do
        from = other == from and index or from
      end
      output = scale(name, input, 10 * (from - 1), kind)
      kind = FLOATS[kind] and kind or nil
    else
      output = convert(name, input, kind)
    end
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

---Runs a size helper: converts `value` from the unit among the options to `target` and remembers how to show it.
---@param name string
---@param target integer index into UNITS
---@param value any
---@param ... any
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

---C's `sizeof` for a type name or a value, in bytes.
---@param operand_ any
---@return integer
local function sizeof(operand_)
  if typed(operand_) then
    return KINDS[operand_.kind].bits / 8
  elseif floating(operand_) then
    return 4
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
