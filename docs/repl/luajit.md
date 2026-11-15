# Number-base helpers in LuaJIT

Every row below was run in LuaJIT; `tests/repl.sh` runs each one again and compares. The first column is typed
at the prompt and the second is what LuaJIT printed: LuaJIT prints a value only for a line that starts with
`=`, so every expression below does. [README.md](README.md) has the rules all four REPLs share and what
differs between them.

## The result line

`bin`, `oct`, `dec` and `hex` return their number, so they nest in arithmetic. The result line shows the
statement's value once, in the base of the helper called last; arithmetic after the call keeps that base.

| Input | Result |
|---|---|
| `=hex(255)` | `0xFF` |
| `=bin(10)` | `0b1010` |
| `=oct(8)` | `0o10` |
| `=dec(0x10)` | `16` |
| `=bin(lshift(hex(0x10), 2))` | `0b1000000` |
| `=hex(1) + bin(2)` | `0b11` |
| `=hex(lshift(hex(bin(0x1000) * 64), 4)) - 0x100` | `0x3FFF00` |
| `=hex(255) + 1` | `0x100` |
| `=1 + hex(255)` | `0x100` |
| `=dec(hex(255))` | `255` |
| `=hex(dec(255))` | `0xFF` |
| `x = hex(16)` | *(nothing)* |
| `=x` | `16` |
| `=x + 1` | `17` |
| `=7` | `7` |
| `=tostring(hex(255))` | `255` |
| `print(hex(255))` | `0xFF` |
| `print(hex(255) + 1)` | `0x100` |

A statement without `=` prints nothing, as `x = hex(16)` above. `print` shows a number in the base called last
in the same statement.

## A base as an option

A base name after the value shows the value in that base instead of the helper's own. It is written bare, or
as a constant or a string, in any letter case.

| Input | Result |
|---|---|
| `=bin(5, hex)` | `0x5` |
| `=hex(5, bin)` | `0b101` |
| `=dec(255, oct)` | `0o377` |
| `=oct(8, dec)` | `8` |
| `=hex(255, "bin")` | `0b11111111` |
| `=hex(255, "BIN")` | `0b11111111` |
| `=hex(255, " bin ")` | `0b11111111` |
| `=hex(5, hex)` | `0x5` |
| `=hex(5, bin, bin)` | `0b101` |
| `=hex(-1, u8, bin)` | `0b11111111` |
| `=hex(-1, bin, u8)` | `0b11111111` |

## With no type: u64

A number with no type written is a `u64`: it is converted to one; a 64-bit cdata number keeps its own type. A
negative number shows its two's complement pattern.

| Input | Result |
|---|---|
| `=hex(0)` | `0x0` |
| `=hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `=dec(-1)` | `18446744073709551615` |
| `=oct(-1)` | `0o1777777777777777777777` |
| `=bin(-1)` | `0b1111111111111111111111111111111111111111111111111111111111111111` |
| `=dec(-8)` | `18446744073709551608` |
| `=hex(bnot(0x1000))` | `0xFFFFFFFFFFFFEFFF` |
| `=dec(bnot(0x1000))` | `18446744073709547519` |
| `=hex(0xFFFFFFFFFFFFFFFFULL)` | `0xFFFFFFFFFFFFFFFF` |
| `=dec(0xFFFFFFFFFFFFFFFFULL)` | `18446744073709551615` |
| `=hex(0x8000000000000000ULL)` | `0x8000000000000000` |
| `=hex(-9223372036854775807LL - 1)` | `0x8000000000000000` |
| `=dec(-9223372036854775807LL - 1)` | `-9223372036854775808` |
| `x = hex(-1)` | *(nothing)* |
| `=x` | `18446744073709551615` |
| `x = hex(-1LL)` | *(nothing)* |
| `=x.type` | `s64` |

## Types

A type after the value converts it as a C cast does on x86-64 Linux: `u8` to `u64` are unsigned, `s8` to `s64`
signed, `f32` and `f64` floats. In `hex`, `bin` and `oct` an integer shows the two's complement pattern of its
type; in `dec` it reads as the type says.

Each cell is the result line of the call in its column header, with `TYPE` replaced by the row's first cell.

| TYPE | `=hex(-200, TYPE)` | `=dec(-200, TYPE)` | `=oct(-200, TYPE)` | `=bin(-200, TYPE)` |
|---|---|---|---|---|
| `u8` | `0x38` | `56` | `0o70` | `0b111000` |
| `s8` | `0x38` | `56` | `0o70` | `0b111000` |
| `u16` | `0xFF38` | `65336` | `0o177470` | `0b1111111100111000` |
| `s16` | `0xFF38` | `-200` | `0o177470` | `0b1111111100111000` |
| `u32` | `0xFFFFFF38` | `4294967096` | `0o37777777470` | `0b11111111111111111111111100111000` |
| `s32` | `0xFFFFFF38` | `-200` | `0o37777777470` | `0b11111111111111111111111100111000` |
| `u64` | `0xFFFFFFFFFFFFFF38` | `18446744073709551416` | `0o1777777777777777777470` | `0b1111111111111111111111111111111111111111111111111111111100111000` |
| `s64` | `0xFFFFFFFFFFFFFF38` | `-200` | `0o1777777777777777777470` | `0b1111111111111111111111111111111111111111111111111111111100111000` |
| `f32` | `-0xC8` | `-200` | `-0o310` | `-0b11001000` |
| `f64` | `-0xC8` | `-200` | `-0o310` | `-0b11001000` |

| TYPE | `=hex(0x123456789, TYPE)` | `=dec(0x123456789, TYPE)` | `=oct(0x123456789, TYPE)` | `=bin(0x123456789, TYPE)` |
|---|---|---|---|---|
| `u8` | `0x89` | `137` | `0o211` | `0b10001001` |
| `s8` | `0x89` | `-119` | `0o211` | `0b10001001` |
| `u16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `s16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `u32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `s32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `u64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `s64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `f32` | `0x123456800` | `4886718464` | `0o44321264000` | `0b100100011010001010110100000000000` |
| `f64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |

### Spelling a type

A type is written bare, as a constant or as a string; letter case and the space around it do not matter, and
naming the same type twice is not a conflict.

| Input | Result |
|---|---|
| `=hex(-1, u16)` | `0xFFFF` |
| `=hex(-1, "u16")` | `0xFFFF` |
| `=hex(-1, "U16")` | `0xFFFF` |
| `=hex(-1, " u16 ")` | `0xFFFF` |
| `=hex(-1, u16, "u16")` | `0xFFFF` |
| `=hex(-1, u16, "uint16_t")` | `0xFFFF` |

### C type names

A type can be spelled as C spells it. The sizes are those of x86-64 Linux (LP64): `char` is 8 bits and signed,
`short` 16, `int` 32, `long` and `long long` 64. The words of a multi-word type come in any order, as in C.

| TYPE | `=hex(-1, TYPE)` | `=dec(-1, TYPE)` | `=sizeof(TYPE)` |
|---|---|---|---|
| `"char"` | `0xFF` | `-1` | `1` |
| `"signed char"` | `0xFF` | `-1` | `1` |
| `"unsigned char"` | `0xFF` | `255` | `1` |
| `"short"` | `0xFFFF` | `-1` | `2` |
| `"short int"` | `0xFFFF` | `-1` | `2` |
| `"signed short"` | `0xFFFF` | `-1` | `2` |
| `"unsigned short"` | `0xFFFF` | `65535` | `2` |
| `"ushort"` | `0xFFFF` | `65535` | `2` |
| `"int"` | `0xFFFFFFFF` | `-1` | `4` |
| `"signed"` | `0xFFFFFFFF` | `-1` | `4` |
| `"signed int"` | `0xFFFFFFFF` | `-1` | `4` |
| `"unsigned"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"unsigned int"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"uint"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"long"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"long int"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"signed long"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"unsigned long"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"long unsigned int"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"ulong"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"long long"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"long long int"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"unsigned long long"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"int8_t"` | `0xFF` | `-1` | `1` |
| `"uint8_t"` | `0xFF` | `255` | `1` |
| `"int16_t"` | `0xFFFF` | `-1` | `2` |
| `"uint16_t"` | `0xFFFF` | `65535` | `2` |
| `"int32_t"` | `0xFFFFFFFF` | `-1` | `4` |
| `"uint32_t"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"int64_t"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"uint64_t"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"size_t"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"ssize_t"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"intptr_t"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"uintptr_t"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"ptrdiff_t"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"intmax_t"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"uintmax_t"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"float"` | `-0x1` | `-1` | `4` |
| `"double"` | `-0x1` | `-1` | `8` |

## Converting

The type names are functions as well: `u16(x)` is C's `(uint16_t)x`. The result is a value that carries its
type. A number is a double: its fraction is dropped and the rest is cut to the type, also where C leaves the
conversion undefined.

| TYPE | `=TYPE(300)` | `=TYPE(-1)` | `=TYPE(0x123456789)` | `=TYPE(3.9)` | `=TYPE(-3.9)` |
|---|---|---|---|---|---|
| `u8` | `44` | `255` | `137` | `3` | `253` |
| `s8` | `44` | `-1` | `-119` | `3` | `-3` |
| `u16` | `300` | `65535` | `26505` | `3` | `65533` |
| `s16` | `300` | `-1` | `26505` | `3` | `-3` |
| `u32` | `300` | `4294967295` | `591751049` | `3` | `4294967293` |
| `s32` | `300` | `-1` | `591751049` | `3` | `-3` |
| `u64` | `300` | `18446744073709551615` | `4886718345` | `3` | `18446744073709551613` |
| `s64` | `300` | `-1` | `4886718345` | `3` | `-3` |
| `f32` | `300` | `-1` | `4886718464` | `3.9000000953674` | `-3.9000000953674` |
| `f64` | `300` | `-1` | `4886718345` | `3.9` | `-3.9` |

| Input | Result |
|---|---|
| `=s64(s32(-1))` | `-1` |
| `=u64(s32(-1))` | `18446744073709551615` |
| `=u8(s16(-1))` | `255` |
| `=s8(u8(200))` | `-56` |
| `=u16(s8(-1))` | `65535` |
| `=s16(1e10)` | `-7168` |
| `=s32(1e10)` | `1410065408` |
| `=u32(1e10)` | `1410065408` |
| `=s64(1e20)` | `s64: 100000000000000000000 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`7766279631452241920` |
| `=u64(1e20)` | `u64: 100000000000000000000 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`7766279631452241920` |
| `=u64(-1.5)` | `18446744073709551615` |
| `=s8(-128.9)` | `-128` |
| `=u8(255.9)` | `255` |
| `=u8(256.0)` | `0` |
| `=f32(0.1)` | `0.10000000149012` |
| `=f32(16777217)` | `16777216` |
| `=f64(1)` | `1` |
| `=f64(u64(-1))` | `1.844674407371e+19` |
| `=f32(u64(-1))` | `1.844674407371e+19` |
| `=f32(1e39)` | `inf` |

### cast and sizeof

`cast(type, value)` converts to a type under any of its spellings. `sizeof` takes a type or a value and
answers in bytes.

`sizeof` returns a `u64`, C's `size_t`, so arithmetic on it is unsigned. A plain number counts as the constant
it would be in C, or as a `double` when it has a fraction.

| Input | Result |
|---|---|
| `=cast("int", 0xFFFFFFFF)` | `-1` |
| `=cast("unsigned char", 300)` | `44` |
| `=cast(u16, 0x12345)` | `9029` |
| `=cast("size_t", -1)` | `18446744073709551615` |
| `=cast("float", 0.1)` | `0.10000000149012` |
| `=cast("double", 1)` | `1` |
| `=sizeof("int")` | `4` |
| `=sizeof(u8)` | `1` |
| `=sizeof("unsigned long")` | `8` |
| `=sizeof(f32)` | `4` |
| `=sizeof(u8(1))` | `1` |
| `=sizeof(u8(1) + u8(1))` | `4` |
| `=sizeof(5)` | `4` |
| `=sizeof(2 ^ 40)` | `8` |
| `=sizeof(1.5)` | `8` |
| `=sizeof("int") - 5` | `18446744073709551615` |

## Arithmetic

A typed value computes by C's rules, as GCC does on x86-64 Linux. `x.type` names the type of a result.

### Integer promotion

An operand narrower than `s32`, C's `int`, becomes an `s32` first, so the narrow types do not wrap in
arithmetic. Convert the result to cut it.

| Input | Result |
|---|---|
| `=u8(250) + u8(10)` | `260` |
| `=(u8(250) + u8(10)).type` | `s32` |
| `=u8(u8(250) + u8(10))` | `4` |
| `=s8(-128) - 1` | `-129` |
| `=u16(0xFFFF) * u16(0xFFFF)` | `-131071` |
| `=-u8(1)` | `-1` |
| `=(-u8(1)).type` | `s32` |
| `=bnot(u8(0))` | `-1` |
| `=(bnot(u8(0))).type` | `s32` |

### The common type

Of two operands the wider type wins, and of two equally wide ones the unsigned.

| Input | Result |
|---|---|
| `=(s32(1) + u32(1)).type` | `u32` |
| `=(u32(1) + s64(1)).type` | `s64` |
| `=(s64(1) + u64(1)).type` | `u64` |
| `=(u16(1) + s8(1)).type` | `s32` |
| `=(u8(1) + s64(1)).type` | `s64` |
| `=s32(-1) + u32(1)` | `0` |
| `=u32(5) - 6` | `4294967295` |
| `=s32(-1) + u64(1)` | `0` |
| `=s64(-1) + u32(1)` | `0` |

### Plain numbers

A number with no fraction beside a typed value is typed as a decimal C constant is: `s32` when it fits, else
`s64`, else `u64`. A negative one is typed by its size, as C types `-2147483648`. A number with a fraction
makes the result a plain number. `LL` and `ULL` numbers are `s64` and `u64`. Two plain numbers stay LuaJIT's
own.

| Input | Result |
|---|---|
| `=(u8(1) + 1).type` | `s32` |
| `=(u8(1) + 2147483647).type` | `s32` |
| `=(u8(1) + 2147483648).type` | `s64` |
| `=(u8(1) - 2147483648).type` | `s64` |
| `=(u8(1) + 0xFFFFFFFFFFFFFFFFULL).type` | `u64` |
| `=(u32(1) + 1).type` | `u32` |
| `=u32(1) + 2 ^ 40` | `1099511627777` |
| `=1 + u8(5)` | `6` |
| `=10 - u32(11)` | `4294967295` |
| `=u8(5) * 1.5` | `7.5` |
| `=1.5 + u8(5)` | `6.5` |
| `=u8(7) / 2` | `3` |
| `=u8(7) / 2.5` | `2.8` |
| `=-7 / 2` | `-3.5` |
| `=s32(-7) / 2` | `-3` |
| `=5LL + u8(1)` | `6` |
| `=(5ULL + u8(1)).type` | `u64` |

### Overflow

A result is cut to its type. A signed result wraps too, as GCC's `-fwrapv` defines it.

| Input | Result |
|---|---|
| `=u32(0xFFFFFFFF) + 1` | `0` |
| `=s32(0x7FFFFFFF) + 1` | `-2147483648` |
| `=u64(-1) + 1` | `0` |
| `=s64(0x7FFFFFFFFFFFFFFFULL) + 1` | `-9223372036854775808` |
| `=u32(0x10000) * u32(0x10000)` | `0` |
| `=s32(-2147483648) - 1` | `2147483647` |
| `=u32(0) - 1` | `4294967295` |
| `=hex(u64(0) - 1)` | `0xFFFFFFFFFFFFFFFF` |
| `=-s32(-2147483648)` | `-2147483648` |

### Division and remainder

`/` truncates toward zero and `%` takes the sign of the dividend. An unsigned type divides as one.

| Input | Result |
|---|---|
| `=s32(-7) / 2` | `-3` |
| `=s32(-7) % 2` | `-1` |
| `=s32(7) / -2` | `-3` |
| `=s32(7) % -2` | `1` |
| `=s32(-7) / -2` | `3` |
| `=u32(-7) / 2` | `2147483644` |
| `=s32(-7) / u32(2)` | `2147483644` |
| `=u64(-1) / 3` | `6148914691236517205` |
| `=s64(-1) / 3` | `0` |
| `=u8(7) % 3` | `1` |
| `=s32(-2147483648) / -1` | `-2147483648` |
| `=s32(-2147483648) % -1` | `0` |

### Shifts and bits

Lua has no bit operators: the `bit` library's functions are global and take typed values. The result has the
first operand's promoted type. `rshift` shifts in zeros and `arshift` copies of the sign bit, whatever the
type; a count uses its low 5 or 6 bits, as the library documents and x86-64 does.

| Input | Result |
|---|---|
| `=lshift(u32(1), 31)` | `2147483648` |
| `=lshift(s32(1), 31)` | `-2147483648` |
| `=lshift(u8(1), 8)` | `256` |
| `=lshift(u8(1), 8).type` | `s32` |
| `=hex(rshift(u64(-1), 60))` | `0xF` |
| `=hex(arshift(s64(-1), 60))` | `0xFFFFFFFFFFFFFFFF` |
| `=arshift(s32(-8), 1)` | `-4` |
| `=rshift(s32(-8), 1)` | `2147483644` |
| `=rshift(u32(-8), 1)` | `2147483644` |
| `=arshift(u32(-8), 1)` | `4294967292` |
| `=lshift(u64(1), 64)` | `1` |
| `=lshift(u32(1), 32)` | `1` |
| `=lshift(u32(1), 33)` | `2` |
| `=lshift(1, u8(31))` | `-2147483648` |
| `=hex(band(u32(0xFF00FF00), 0xFFFF))` | `0xFF00` |
| `=hex(bor(u8(0xF0), u8(0x0F)))` | `0xFF` |
| `=bor(u8(1), u8(2)).type` | `s32` |
| `=hex(bxor(u16(0xFFFF), 1))` | `0xFFFE` |
| `=hex(bnot(u64(0xFFF)))` | `0xFFFFFFFFFFFFF000` |
| `=hex(bnot(u8(0)))` | `0xFFFFFFFF` |
| `=hex(rol(u32(0x80000001), 1))` | `0x3` |
| `=hex(ror(u32(1), 1))` | `0x80000000` |
| `=hex(rol(u64(1), 63))` | `0x8000000000000000` |
| `=hex(bswap(u32(0x11223344)))` | `0x44332211` |
| `=hex(bswap(u64(0x1122334455667788ULL)))` | `0x8877665544332211` |
| `=tohex(u32(255))` | `000000ff` |
| `=band(0xFF, 0x0F)` | `15` |

### Comparison

Both sides are converted to the common type first, so a negative number beside an unsigned one compares as a
large number.

| Input | Result |
|---|---|
| `=s32(-1) < u32(1)` | `false` |
| `=s32(-1) < 1` | `true` |
| `=s32(-1) == u32(0xFFFFFFFF)` | `true` |
| `=s64(-1) < u64(0)` | `false` |
| `=s64(-1) < u32(0)` | `true` |
| `=u8(255) > s8(-1)` | `true` |
| `=u8(5) == 5` | `true` |
| `=5 == u8(5)` | `true` |
| `=5 < u8(6)` | `true` |
| `=u8(5) == 5.0` | `true` |
| `=u8(5) < 5.5` | `true` |
| `=u8(5) ~= 5` | `false` |
| `=u8(5) == "5"` | `false` |

### The value itself

`tostring` gives the decimal digits and `..` joins them; `x.type` names the type.

| Input | Result |
|---|---|
| `=u8(250).type` | `u8` |
| `=tostring(u64(-1))` | `18446744073709551615` |
| `=u8(5) .. " apples"` | `5 apples` |
| `=type(u8(5))` | `cdata` |
| `=tostring(s8(-1))` | `-1` |

## Floats

A float keeps its fraction in every base, and negative zero keeps its sign. A float type rounds to that
precision; an integer type drops the fraction.

| Input | Result |
|---|---|
| `=hex(1.5)` | `0x1.8` |
| `=hex(-1.5)` | `-0x1.8` |
| `=hex(0.1)` | `0x0.1999999999999A` |
| `=bin(0.75)` | `0b0.11` |
| `=oct(0.5)` | `0o0.4` |
| `=dec(1.5)` | `1.5` |
| `=hex(-0.0)` | `0x0` |
| `=hex(255.0)` | `0xFF` |
| `=hex(2.5) * 2` | `0x5` |
| `=hex(1.5, f32)` | `0x1.8` |
| `=hex(0.1, f32)` | `0x0.199999A` |
| `=hex(0.1, f64)` | `0x0.1999999999999A` |
| `=dec(0.1, f32)` | `0.10000000149012` |
| `=hex(255, f32)` | `0xFF` |
| `=hex(1.5, u8)` | `0x1` |
| `=hex(-1.5, u8)` | `0xFF` |
| `=hex(1e39, f32)` | `inf` |

### Single precision

`f32` returns a single-precision value, which computes as C's `float` does: `+`, `-`, `*` and `/` round their result to single precision, a whole number or a typed integer beside it is converted to single precision first, and a number with a fraction, C's `double`, makes the result a number. A whole number always counts as an integer constant, also when it came from `f64`.

| Input | Result |
|---|---|
| `=f32(0.1) + f32(0.2)` | `0.30000001192093` |
| `=f32(0.1) + 0.2` | `0.30000000149012` |
| `=f32(1) / 3` | `0.33333334326744` |
| `=1 / f32(3)` | `0.33333334326744` |
| `=f32(16777216) + 1` | `16777216` |
| `=u32(16777217) + f32(0)` | `16777216` |
| `=f32(0.1) * f32(0.1)` | `0.010000000707805` |
| `=-f32(1.5)` | `-1.5` |
| `=f32(1) / 0` | `inf` |
| `=f32(1) < 2` | `true` |
| `=s32(1) < f32(1.5)` | `true` |
| `=u32(16777217) == f32(16777216)` | `true` |
| `=hex(f32(0.1))` | `0x0.199999A` |
| `=u8(f32(3.9))` | `3` |
| `=f64(f32(0.1))` | `0.10000000149012` |
| `=sizeof(f32(1))` | `4` |
| `=kb(f32(1536))` | `1.5` |

## Booleans, characters and other values

`true` and `false` are 1 and 0, and a string of one character is its code point.

| Input | Result |
|---|---|
| `=hex(true)` | `0x1` |
| `=hex(false)` | `0x0` |
| `=hex("A")` | `0x41` |
| `=dec("A")` | `65` |
| `=hex("가")` | `0xAC00` |
| `=hex("𝄞")` | `0x1D11E` |
| `=u8("A")` | `65` |
| `=hex(255ULL)` | `0xFF` |
| `=hex(-1LL)` | `0xFFFFFFFFFFFFFFFF` |
| `=dec(0xFFFFFFFFFFFFFFFFULL, s64)` | `-1` |
| `=hex(255LL, u8)` | `0xFF` |

## Notes on standard error

A number past 2^53 is no longer exact, and a helper says so once in a statement; one at or past 2^64 is cut to
its low 64 as well. `ULL` and `LL` numbers are exact.

| Input | Result |
|---|---|
| `=hex(2 ^ 53)` | `hex: 9007199254740992 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`0x20000000000000` |
| `=hex(2 ^ 53 - 1)` | `0x1FFFFFFFFFFFFF` |
| `=hex(0xffffffff81001234)` | `hex: 18446744071578849280 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`0xFFFFFFFF81001000` |
| `=hex(0xffffffff81001234ULL)` | `0xFFFFFFFF81001234` |
| `=hex(2 ^ 64)` | `hex: 18446744073709551616 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`hex: the value is wider than 64 bits and was cut to the low 64`<br>`0x0` |
| `=hex(-2 ^ 64)` | `hex: -18446744073709551616 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`hex: the value is wider than 64 bits and was cut to the low 64`<br>`0x0` |
| `=u64(2 ^ 64)` | `u64: 18446744073709551616 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`0` |
| `=hex(2 ^ 64, u64)` | `hex: 18446744073709551616 is past 2^53, where a number is no longer exact; write it as a 64-bit literal (0x...ULL)`<br>`0x0` |

## Errors

A statement that fails prints no result line, and the next statement starts clean. LuaJIT prints the message
and then a stack traceback.

### Values

| Input | Error |
|---|---|
| `=hex(nil)` | `hex expects a number, 64-bit integer, boolean, or single character, got nil` |
| `=hex()` | `hex expects a number, 64-bit integer, boolean, or single character, got nil` |
| `=hex("AB")` | `hex expects a single character, got "AB" (2 code points)` |
| `=hex("")` | `hex expects a single character, got "" (0 code points)` |
| `=hex({})` | `hex expects a number, 64-bit integer, boolean, or single character, got table` |
| `=hex(print)` | `hex expects a number, 64-bit integer, boolean, or single character, got function` |
| `=hex(0/0)` | `hex expects a finite number, got nan` |
| `=hex(1/0)` | `hex expects a finite number, got inf` |
| `=hex("\255")` | `hex expects valid UTF-8, got "\255"` |
| `=u8("AB")` | `u8 expects a single character, got "AB" (2 code points)` |
| `=u8(nil)` | `u8 expects a number, 64-bit integer, boolean, or single character, got nil` |
| `=f32(0/0)` | `f32 expects a finite number, got nan` |

### Options

| Input | Error |
|---|---|
| `=hex(1, "foo")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "foo"` |
| `=hex(1, 16)` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got 16` |
| `=hex(1, nil)` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got nil` |
| `=hex(1, "u128")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "u128"` |
| `=hex(1, "long long long")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "long long long"` |
| `=hex(1, "unsigned signed")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "unsigned signed"` |
| `=hex(1, "char int")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "char int"` |
| `=hex(1, "short long")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "short long"` |
| `=hex(1, "long double")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "long double"` |
| `=hex(1, "")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got ""` |
| `=hex(1, "int int")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "int int"` |
| `=hex(1, u8, u16)` | `hex takes one type, got u8 and u16` |
| `=hex(1, bin, oct)` | `hex takes one base, got bin and oct` |
| `=hex(1, "int", "long")` | `hex takes one type, got s32 and s64` |
| `=hex(1, u8, bin, s8)` | `hex takes one type, got u8 and s8` |
| `=hex(1, "big")` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "big"` |

### The type functions, cast and sizeof

| Input | Error |
|---|---|
| `=u8(1, 2)` | `u8 takes one value, got 2` |
| `=u8()` | `u8 takes one value, got 0` |
| `=cast(hex, 1)` | `cast expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got function` |
| `=cast("foo", 1)` | `cast expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "foo"` |
| `=cast("int")` | `cast expects a number, 64-bit integer, boolean, or single character, got nil` |
| `=cast("int", "AB")` | `cast expects a single character, got "AB" (2 code points)` |
| `=sizeof(nil)` | `sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got nil` |
| `=sizeof("foo")` | `sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "foo"` |
| `=sizeof(hex)` | `sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got function` |

### Typed arithmetic

A division by zero is undefined in C and stops the x86-64 instruction; here it is an error. A plain number
wider than 64 bits has no C type to take.

| Input | Error |
|---|---|
| `=u32(7) / 0` | `attempt to divide by zero` |
| `=u32(7) % 0` | `attempt to divide by zero` |
| `=s32(7) / u8(0)` | `attempt to divide by zero` |
| `=7 / u8(0)` | `attempt to divide by zero` |
| `=u8(1) + "x"` | `attempt to perform integer arithmetic on "x"` |
| `=u8(1) + nil` | `attempt to perform integer arithmetic on nil` |
| `=u8(1) + 2 ^ 64` | `18446744073709551616 is wider than 64 bits, so it has no C type; convert it with u64 or another type` |
| `=lshift(u8(1), 1.5)` | `attempt to perform integer arithmetic on 1.5` |
| `=band(u8(1), 1.5)` | `attempt to perform integer arithmetic on 1.5` |
| `=u8(1) < "x"` | `attempt to perform integer arithmetic on "x"` |

## Sizes

`byte`, `kb`, `mb`, `gb` and `tb` convert a size to their unit, in steps of 1024.

### To a unit

The value is in bytes.

| Input | Result |
|---|---|
| `=gb(0x40000000)` | `1` |
| `=mb(0x200000)` | `2` |
| `=kb(4096)` | `4` |
| `=tb(0x7F0000000000)` | `127` |
| `=byte(4096)` | `4096` |
| `=kb("A")` | `0.06347` |
| `=kb(true)` | `0.00097` |

### From a unit

A unit after the value says what the value is in. It is a bare name or a string, in any letter case, short or spelled out.

| Input | Result |
|---|---|
| `=gb(512, mb)` | `0.5` |
| `=byte(4, gb)` | `4294967296` |
| `=byte(1.5, kb)` | `1536` |
| `=kb(1, gb)` | `1048576` |
| `=tb(512, gb)` | `0.5` |
| `=mb(3, gb)` | `3072` |
| `=tb(5, tb)` | `5` |
| `=gb(512, "Megabyte")` | `0.5` |
| `=gb(512, "MiB")` | `0.5` |
| `=gb(512, "megabytes")` | `0.5` |
| `=byte(1, "GiB")` | `1073741824` |
| `=kb(1, "Terabyte")` | `1073741824` |
| `=mb(1048576, "b")` | `1` |

### Both units in the name

`A_to_B(x)` is `B(x, A)`, for each pair of `byte`, `kb`, `mb`, `gb` and `tb`.

| Input | Result |
|---|---|
| `=mb_to_gb(512)` | `0.5` |
| `=gb_to_byte(4)` | `4294967296` |
| `=kb_to_mb(1536)` | `1.5` |
| `=tb_to_gb(2)` | `2048` |
| `=byte_to_kb(1024)` | `1` |
| `=gb_to_tb(1)` | `0.00097` |
| `=mb_to_kb(3)` | `3072` |
| `=byte_to_tb(1)` | `0.0000000000009094947` |
| `=gb_to_mb(1, u8)` | `1024` |

### A result that is not whole

When the division leaves a remainder the result is a float: shown to 5 places, cut and not rounded, or to 20 when the first 5 are zeros. A whole result has no fraction.

| Input | Result |
|---|---|
| `=kb(1000)` | `0.97656` |
| `=kb(1025)` | `1.00097` |
| `=mb(0x1234567)` | `18.20444` |
| `=gb(1.5e9)` | `1.39698` |
| `=kb(1023.999999)` | `0.99999` |
| `=mb(1)` | `0.00000095367431640625` |
| `=gb(1)` | `0.00000000093132257461` |
| `=tb(1)` | `0.0000000000009094947` |
| `=gb(0x1000)` | `0.000003814697265625` |
| `=kb(-2048.5)` | `-2.00048` |
| `=kb(1e-30)` | `9.765625e-34` |
| `=kb(2048.5 - 0.5)` | `2` |

### In arithmetic

A conversion returns its number, and the result line follows the helper called last.

| Input | Result |
|---|---|
| `=gb(byte(1024))` | `0.00000095367431640625` |
| `=hex(byte(2, mb))` | `0x200000` |
| `=gb(0x40000000) + 1` | `2` |
| `=mb(1, gb) * 1.5` | `1536` |
| `=bin(kb(4096))` | `0b100` |
| `=dec(gb(1, tb))` | `1024` |

### With a type

A type among the options converts the value first, as a C cast does, and the constant is then multiplied or divided as C would: the division truncates and the product is cut. Without one a whole number is a `u64`, and a typed value keeps its type unless the division leaves a remainder.

| Input | Result |
|---|---|
| `=gb(0x1000, u64)` | `0` |
| `=byte(4, gb, u32)` | `0` |
| `=byte(4, tb, u32)` | `4398046511104` |
| `=kb(-2048)` | `18014398509481982` |
| `=kb(-2048, s64)` | `-2` |
| `=kb(-2049, s64)` | `-2` |
| `=kb(200, mb, u8)` | `204800` |
| `=kb(-1, u32)` | `4194303` |
| `=kb(-4096, "int")` | `-4` |
| `=gb(1, f32)` | `0.00000000093132257461` |
| `=gb(0x1000, f64)` | `0.000003814697265625` |
| `=gb(0x1000ULL)` | `0.000003814697265625` |
| `=kb(-2048LL)` | `-2` |
| `=gb(u64(0x1000))` | `0.000003814697265625` |
| `=byte(u32(4), gb)` | `0` |
| `=kb(s32(-4096))` | `-4` |
| `=kb(s32(-4097))` | `-4.00097` |
| `=kb(u8(200), mb)` | `204800` |

### Errors

| Input | Error |
|---|---|
| `=gb(1, mb, kb)` | `gb takes one unit, got mb and kb` |
| `=mb_to_gb(1, kb)` | `mb_to_gb takes one unit, got mb and kb` |
| `=gb(1, hex)` | `gb expects options among byte, kb, mb, gb, tb, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got function` |
| `=gb(1, u16, s8)` | `gb takes one type, got u16 and s8` |
| `=gb(nil)` | `gb expects a number, 64-bit integer, boolean, or single character, got nil` |
| `=gb("AB")` | `gb expects a single character, got "AB" (2 code points)` |
| `=hex(1, mb)` | `hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got function` |
| `=gb(1, "furlong")` | `gb expects options among byte, kb, mb, gb, tb, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64 or a C type name, got "furlong"` |

## A helper without a value

A bare name is the function itself, which is how `u16` or `hex` works as an option. The functions of LuaJIT's
`bit` library are global here as well, and take typed values.

| Input | Result |
|---|---|
| `=type(hex)` | `function` |
| `=type(u16)` | `function` |
| `=type(cast)` | `function` |
| `=type(band)` | `function` |
| `=band(0xFF, 0x0F)` | `15` |
| `=tohex(255)` | `000000ff` |

## Without the REPL's hooks

The single result line needs a metatable on `_G` and the global `print`. Where one is missing, each helper
prints its own value when it is called and the result line is LuaJIT's usual one:

```text
> =bin(hex(5) + 1)
0x5
0b110
6
```

## Outside an interactive REPL

`LUA_INIT` runs in every LuaJIT, and in every other `lua` too, but the file defines nothing unless LuaJIT
starts an interactive REPL: not under `-e`, a script or a pipe, and never in another Lua.

```text
$ luajit -e 'print(hex)'
nil
```
