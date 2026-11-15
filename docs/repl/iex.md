# Number-base helpers in IEx

Every row below was run in IEx; `tests/repl.sh` runs each one again and compares. The first column is typed at
the prompt and the second is what IEx printed: the result line is the one IEx prints after a statement.
[README.md](README.md) has the rules all four REPLs share and what differs between them.

## The result line

`bin`, `oct`, `dec` and `hex` return their number, so they nest in arithmetic. The result line shows the
statement's value once, in the base of the helper called last; arithmetic after the call keeps that base.

| Input | Result |
|---|---|
| `hex(255)` | `0xFF` |
| `bin(10)` | `0b1010` |
| `oct(8)` | `0o10` |
| `dec(0x10)` | `16` |
| `bin(hex(0x10) <<< 2)` | `0b1000000` |
| `hex(1) + bin(2)` | `0b11` |
| `hex(hex(bin(0x1000) * 64) <<< 4) - 0x100` | `0x3FFF00` |
| `hex(255) + 1` | `0x100` |
| `1 + hex(255)` | `0x100` |
| `dec(hex(255))` | `255` |
| `hex(dec(255))` | `0xFF` |
| `x = hex(16)` | `0x10` |
| `x` | `16` |
| `x + 1` | `17` |
| `7` | `7` |
| `[hex(1), bin(2)]` | `[1, 2]` |
| `to_string(hex(255))` | `"255"` |
| `hex(1); bin(2)` | `0b10` |
| `255 \|> hex() \|> bin()` | `0b11111111` |

## A base as an option

A base name after the value shows the value in that base instead of the helper's own. It is written bare, or
as a constant or a string, in any letter case.

| Input | Result |
|---|---|
| `bin(5, hex)` | `0x5` |
| `hex(5, bin)` | `0b101` |
| `dec(255, oct)` | `0o377` |
| `oct(8, dec)` | `8` |
| `hex(255, :bin)` | `0b11111111` |
| `hex(255, "bin")` | `0b11111111` |
| `hex(255, "BIN")` | `0b11111111` |
| `hex(255, " bin ")` | `0b11111111` |
| `hex(5, hex)` | `0x5` |
| `hex(5, bin, bin)` | `0b101` |
| `hex(-1, u8, bin)` | `0b11111111` |
| `hex(-1, bin, u8)` | `0b11111111` |

## With no type: u64

A number with no type written is a `u64`: it is converted to one. A negative number shows its two's complement
pattern.

| Input | Result |
|---|---|
| `hex(0)` | `0x0` |
| `hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `dec(-1)` | `18446744073709551615` |
| `oct(-1)` | `0o1777777777777777777777` |
| `bin(-1)` | `0b1111111111111111111111111111111111111111111111111111111111111111` |
| `dec(-8)` | `18446744073709551608` |
| `hex(bnot(0x1000))` | `0xFFFFFFFFFFFFEFFF` |
| `dec(bnot(0x1000))` | `18446744073709547519` |
| `hex(0xFFFFFFFFFFFFFFFF)` | `0xFFFFFFFFFFFFFFFF` |
| `dec(0xFFFFFFFFFFFFFFFF)` | `18446744073709551615` |
| `hex(0x8000000000000000)` | `0x8000000000000000` |
| `hex(-(1 <<< 63))` | `0x8000000000000000` |
| `dec(-(1 <<< 63))` | `9223372036854775808` |
| `x = hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `x` | `18446744073709551615` |

## Types

A type after the value converts it as a C cast does on x86-64 Linux: `u8` to `u64` are unsigned, `s8` to `s64`
signed, `f32` and `f64` floats, and `big` has no width. In `hex`, `bin` and `oct` an integer shows the two's
complement pattern of its type; in `dec` it reads as the type says. `big` shows a sign instead.

Each cell is the result line of the call in its column header, with `TYPE` replaced by the row's first cell.

| TYPE | `hex(-200, TYPE)` | `dec(-200, TYPE)` | `oct(-200, TYPE)` | `bin(-200, TYPE)` |
|---|---|---|---|---|
| `u8` | `0x38` | `56` | `0o70` | `0b111000` |
| `s8` | `0x38` | `56` | `0o70` | `0b111000` |
| `u16` | `0xFF38` | `65336` | `0o177470` | `0b1111111100111000` |
| `s16` | `0xFF38` | `-200` | `0o177470` | `0b1111111100111000` |
| `u32` | `0xFFFFFF38` | `4294967096` | `0o37777777470` | `0b11111111111111111111111100111000` |
| `s32` | `0xFFFFFF38` | `-200` | `0o37777777470` | `0b11111111111111111111111100111000` |
| `u64` | `0xFFFFFFFFFFFFFF38` | `18446744073709551416` | `0o1777777777777777777470` | `0b1111111111111111111111111111111111111111111111111111111100111000` |
| `s64` | `0xFFFFFFFFFFFFFF38` | `-200` | `0o1777777777777777777470` | `0b1111111111111111111111111111111111111111111111111111111100111000` |
| `f32` | `-0xC8` | `-200.0` | `-0o310` | `-0b11001000` |
| `f64` | `-0xC8` | `-200.0` | `-0o310` | `-0b11001000` |
| `big` | `-0xC8` | `-200` | `-0o310` | `-0b11001000` |

| TYPE | `hex(0x123456789, TYPE)` | `dec(0x123456789, TYPE)` | `oct(0x123456789, TYPE)` | `bin(0x123456789, TYPE)` |
|---|---|---|---|---|
| `u8` | `0x89` | `137` | `0o211` | `0b10001001` |
| `s8` | `0x89` | `-119` | `0o211` | `0b10001001` |
| `u16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `s16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `u32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `s32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `u64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `s64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `f32` | `0x123456800` | `4886718464.0` | `0o44321264000` | `0b100100011010001010110100000000000` |
| `f64` | `0x123456789` | `4886718345.0` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `big` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |

### Spelling a type

A type is written bare, as a constant or as a string; letter case and the space around it do not matter, and
naming the same type twice is not a conflict.

| Input | Result |
|---|---|
| `hex(-1, u16)` | `0xFFFF` |
| `hex(-1, :u16)` | `0xFFFF` |
| `hex(-1, "u16")` | `0xFFFF` |
| `hex(-1, "U16")` | `0xFFFF` |
| `hex(-1, " u16 ")` | `0xFFFF` |
| `hex(-1, :U16)` | `0xFFFF` |
| `hex(-1, u16, :u16)` | `0xFFFF` |
| `hex(-1, u16, :uint16_t)` | `0xFFFF` |

### C type names

A type can be spelled as C spells it. The sizes are those of x86-64 Linux (LP64): `char` is 8 bits and signed,
`short` 16, `int` 32, `long` and `long long` 64. The words of a multi-word type come in any order, as in C.

| TYPE | `hex(-1, TYPE)` | `dec(-1, TYPE)` | `sizeof(TYPE)` |
|---|---|---|---|
| `:char` | `0xFF` | `-1` | `1` |
| `"signed char"` | `0xFF` | `-1` | `1` |
| `"unsigned char"` | `0xFF` | `255` | `1` |
| `:short` | `0xFFFF` | `-1` | `2` |
| `"short int"` | `0xFFFF` | `-1` | `2` |
| `"signed short"` | `0xFFFF` | `-1` | `2` |
| `"unsigned short"` | `0xFFFF` | `65535` | `2` |
| `:ushort` | `0xFFFF` | `65535` | `2` |
| `:int` | `0xFFFFFFFF` | `-1` | `4` |
| `:signed` | `0xFFFFFFFF` | `-1` | `4` |
| `"signed int"` | `0xFFFFFFFF` | `-1` | `4` |
| `:unsigned` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"unsigned int"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `:uint` | `0xFFFFFFFF` | `4294967295` | `4` |
| `:long` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"long int"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"signed long"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"unsigned long"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"long unsigned int"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:ulong` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `"long long"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"long long int"` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `"unsigned long long"` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:int8_t` | `0xFF` | `-1` | `1` |
| `:uint8_t` | `0xFF` | `255` | `1` |
| `:int16_t` | `0xFFFF` | `-1` | `2` |
| `:uint16_t` | `0xFFFF` | `65535` | `2` |
| `:int32_t` | `0xFFFFFFFF` | `-1` | `4` |
| `:uint32_t` | `0xFFFFFFFF` | `4294967295` | `4` |
| `:int64_t` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `:uint64_t` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:size_t` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:ssize_t` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `:intptr_t` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `:uintptr_t` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:ptrdiff_t` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `:intmax_t` | `0xFFFFFFFFFFFFFFFF` | `-1` | `8` |
| `:uintmax_t` | `0xFFFFFFFFFFFFFFFF` | `18446744073709551615` | `8` |
| `:float` | `-0x1` | `-1.0` | `4` |
| `:double` | `-0x1` | `-1.0` | `8` |

## Converting

The type names are functions as well: `u16(x)` is C's `(uint16_t)x`. The result is a plain integer, already
cut. A float converts as the instruction GCC emits does (`cvttsd2si`): the fraction is dropped, and a value
outside the register converts to the lowest value, which C leaves undefined.

| TYPE | `TYPE(300)` | `TYPE(-1)` | `TYPE(0x123456789)` | `TYPE(3.9)` | `TYPE(-3.9)` |
|---|---|---|---|---|---|
| `u8` | `44` | `255` | `137` | `3` | `253` |
| `s8` | `44` | `-1` | `-119` | `3` | `-3` |
| `u16` | `300` | `65535` | `26505` | `3` | `65533` |
| `s16` | `300` | `-1` | `26505` | `3` | `-3` |
| `u32` | `300` | `4294967295` | `591751049` | `3` | `4294967293` |
| `s32` | `300` | `-1` | `591751049` | `3` | `-3` |
| `u64` | `300` | `18446744073709551615` | `4886718345` | `3` | `18446744073709551613` |
| `s64` | `300` | `-1` | `4886718345` | `3` | `-3` |
| `f32` | `300.0` | `-1.0` | `4886718464.0` | `3.9000000953674316` | `-3.9000000953674316` |
| `f64` | `300.0` | `-1.0` | `4886718345.0` | `3.9` | `-3.9` |
| `big` | `300` | `-1` | `4886718345` | `3` | `-3` |

| Input | Result |
|---|---|
| `s64(s32(-1))` | `-1` |
| `u64(s32(-1))` | `18446744073709551615` |
| `u8(s16(-1))` | `255` |
| `s8(u8(200))` | `-56` |
| `u16(s8(-1))` | `65535` |
| `s16(1.0e10)` | `0` |
| `s32(1.0e10)` | `-2147483648` |
| `u32(1.0e10)` | `1410065408` |
| `s64(1.0e20)` | `-9223372036854775808` |
| `u64(1.0e20)` | `0` |
| `u64(-1.5)` | `18446744073709551615` |
| `s8(-128.9)` | `-128` |
| `u8(255.9)` | `255` |
| `u8(256.0)` | `0` |
| `f32(0.1)` | `0.10000000149011612` |
| `f32(16777217)` | `16777216.0` |
| `f64(1)` | `1.0` |
| `f64(u64(-1))` | `1.8446744073709552e19` |
| `f32(u64(-1))` | `1.8446744073709552e19` |
| `big(3.9)` | `3` |
| `big(-3.9)` | `-3` |
| `big(u8(255)) + 1` | `256` |

### cast and sizeof

`cast(type, value)` converts to a type under any of its spellings. `sizeof` takes a type or a value and
answers in bytes.

Values carry no type here, so `sizeof` of a number is the size of the constant it would be in C: 4 when it
fits an `int`, else 8, and 8 for a float.

| Input | Result |
|---|---|
| `cast(:int, 0xFFFFFFFF)` | `-1` |
| `cast("unsigned char", 300)` | `44` |
| `cast(u16, 0x12345)` | `9029` |
| `cast(:size_t, -1)` | `18446744073709551615` |
| `cast(:float, 0.1)` | `0.10000000149011612` |
| `cast(:double, 1)` | `1.0` |
| `cast(big, 3.9)` | `3` |
| `sizeof(:int)` | `4` |
| `sizeof(u8)` | `1` |
| `sizeof("unsigned long")` | `8` |
| `sizeof(f32)` | `4` |
| `sizeof(u8(1))` | `4` |
| `sizeof(u8(1) + u8(1))` | `4` |
| `sizeof(5)` | `4` |
| `sizeof(1 <<< 40)` | `8` |
| `sizeof(1.5)` | `8` |
| `sizeof(:int) - 5` | `-1` |

## Arithmetic

IEx cannot change what its operators do, so arithmetic is Elixir's own: integers have no width and never wrap.
A conversion cuts where it is called and no further. `div` and `rem` truncate as C's `/` and `%` do, `/`
always divides as floats, and `>>>` copies the sign.

| Input | Result |
|---|---|
| `0xFFFFFFFF + 1` | `4294967296` |
| `u32(0xFFFFFFFF + 1)` | `0` |
| `u32(0xFFFFFFFF) + 1` | `4294967296` |
| `hex(u32(0xFFFFFFFF) + 1)` | `0x100000000` |
| `hex(u32(0xFFFFFFFF) + 1, u32)` | `0x0` |
| `u8(250) + u8(10)` | `260` |
| `u8(u8(250) + u8(10))` | `4` |
| `-7 / 2` | `-3.5` |
| `div(-7, 2)` | `-3` |
| `rem(-7, 2)` | `-1` |
| `div(7, -2)` | `-3` |
| `rem(7, -2)` | `1` |
| `-8 >>> 1` | `-4` |
| `u32(-8) >>> 1` | `2147483644` |
| `hex(-1) >>> 4` | `0xFFFFFFFFFFFFFFF` |
| `hex(-1, s64) >>> 4` | `0xFFFFFFFFFFFFFFFF` |
| `hex(bnot(0))` | `0xFFFFFFFFFFFFFFFF` |
| `bnot(u8(0))` | `-1` |
| `hex(bnot(u8(0)), u8)` | `0xFF` |
| `s32(-1) < u32(1)` | `true` |
| `hex(band(0xFF00FF00, 0xFFFF))` | `0xFF00` |
| `hex(bor(0xF0, 0x0F))` | `0xFF` |
| `hex(bxor(0xFFFF, 1))` | `0xFFFE` |
| `1 <<< 64` | `18446744073709551616` |
| `u64(1 <<< 64)` | `0` |
| `hex(1 <<< 63)` | `0x8000000000000000` |

## Floats

A float keeps its fraction in every base, and negative zero keeps its sign. A float type rounds to that
precision; an integer type drops the fraction.

| Input | Result |
|---|---|
| `hex(1.5)` | `0x1.8` |
| `hex(-1.5)` | `-0x1.8` |
| `hex(0.1)` | `0x0.1999999999999A` |
| `bin(0.75)` | `0b0.11` |
| `oct(0.5)` | `0o0.4` |
| `dec(1.5)` | `1.5` |
| `hex(-0.0)` | `-0x0` |
| `hex(255.0)` | `0xFF` |
| `hex(2.5) * 2` | `0x5` |
| `hex(1.5, f32)` | `0x1.8` |
| `hex(0.1, f32)` | `0x0.199999A` |
| `hex(0.1, f64)` | `0x0.1999999999999A` |
| `dec(0.1, f32)` | `0.10000000149011612` |
| `hex(255, f32)` | `0xFF` |
| `hex(1.5, u8)` | `0x1` |
| `hex(-1.5, u8)` | `0xFF` |
| `hex(1.5, big)` | `0x1` |

## Booleans, characters and other values

`true` and `false` are 1 and 0, and a string of one character is its code point.

| Input | Result |
|---|---|
| `hex(true)` | `0x1` |
| `hex(false)` | `0x0` |
| `hex("A")` | `0x41` |
| `dec("A")` | `65` |
| `hex("가")` | `0xAC00` |
| `hex("𝄞")` | `0x1D11E` |
| `u8("A")` | `65` |
| `hex(~c"A")` | `0x41` |
| `hex([65])` | `0x41` |

## Notes on standard error

A number wider than 64 bits with no type is cut to its low 64, with a note; a type says how much to keep, so
there is none.

| Input | Result |
|---|---|
| `hex(1 <<< 64)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass :big to keep all of it`<br>`0x0` |
| `hex((1 <<< 64) + 5)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass :big to keep all of it`<br>`0x5` |
| `dec(-(1 <<< 64))` | `dec: the value is wider than 64 bits and was cut to the low 64; pass :big to keep all of it`<br>`0` |
| `hex(1 <<< 64, big)` | `0x10000000000000000` |
| `hex(1 <<< 64, u64)` | `0x0` |
| `hex(1 <<< 100, u8)` | `0x0` |
| `u64(1 <<< 64)` | `0` |
| `hex(hex(1 <<< 100) + 1)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass :big to keep all of it`<br>`0x1` |

## Errors

A statement that fails prints no result line, and the next statement starts clean. IEx prints the message and
then a stack trace.

### Values

| Input | Error |
|---|---|
| `hex(nil)` | `** (ArgumentError) hex expects an integer, float, boolean, or single character, got nil` |
| `hex("AB")` | `** (ArgumentError) hex expects a single character, got "AB" (2 code points)` |
| `hex("")` | `** (ArgumentError) hex expects a single character, got "" (0 code points)` |
| `hex([1, 2])` | `** (ArgumentError) hex expects an integer, float, boolean, or single character, got [1, 2]` |
| `hex(:a)` | `** (ArgumentError) hex expects an integer, float, boolean, or single character, got :a` |
| `hex({1})` | `** (ArgumentError) hex expects an integer, float, boolean, or single character, got {1}` |
| `hex(%{})` | `** (ArgumentError) hex expects an integer, float, boolean, or single character, got %{}` |
| `hex(<<255>>)` | `** (ArgumentError) hex expects valid UTF-8, got <<255>>` |
| `u8("AB")` | `** (ArgumentError) u8 expects a single character, got "AB" (2 code points)` |
| `u8(nil)` | `** (ArgumentError) u8 expects an integer, float, boolean, or single character, got nil` |
| `f32(1.0e39)` | `** (ArgumentError) f32 cannot hold 1.0e39` |
| `hex(1.0e39, f32)` | `** (ArgumentError) f32 cannot hold 1.0e39` |
| `f64(1 <<< 2000)` | `** (ArgumentError) f64 cannot hold 11481306952742545242328332011776819840223177020886952004776427368257662613923...` |

### Options

| Input | Error |
|---|---|
| `hex(1, :foo)` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :foo` |
| `hex(1, "foo")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "foo"` |
| `hex(1, 16)` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 16` |
| `hex(1, nil)` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got nil` |
| `hex(1, :u128)` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :u128` |
| `hex(1, "long long long")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "long long long"` |
| `hex(1, "unsigned signed")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "unsigned signed"` |
| `hex(1, "char int")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "char int"` |
| `hex(1, "short long")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "short long"` |
| `hex(1, "long double")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "long double"` |
| `hex(1, "")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got ""` |
| `hex(1, "int int")` | `** (ArgumentError) hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "int int"` |
| `hex(1, u8, u16)` | `** (ArgumentError) hex takes one type, got u8 and u16` |
| `hex(1, bin, oct)` | `** (ArgumentError) hex takes one base, got bin and oct` |
| `hex(1, :int, :long)` | `** (ArgumentError) hex takes one type, got s32 and s64` |
| `hex(1, u8, bin, s8)` | `error: undefined function hex/4 (there is no such import)` |

### The type functions, cast and sizeof

| Input | Error |
|---|---|
| `u8(1, 2)` | `error: undefined function u8/2 (there is no such import)` |
| `cast(:hex, 1)` | `** (ArgumentError) cast expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :hex` |
| `cast(:foo, 1)` | `** (ArgumentError) cast expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :foo` |
| `cast(:int)` | `error: undefined function cast/1 (there is no such import)` |
| `cast(:int, "AB")` | `** (ArgumentError) cast expects a single character, got "AB" (2 code points)` |
| `sizeof(big)` | `** (ArgumentError) sizeof expects a type with a size, got big` |
| `sizeof(nil)` | `** (ArgumentError) sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got nil` |
| `sizeof(:foo)` | `** (ArgumentError) sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :foo` |
| `sizeof(:hex)` | `** (ArgumentError) sizeof expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :hex` |
| `hex(1, :u8, :hex, :u16)` | `error: undefined function hex/4 (there is no such import)` |

## Sizes

`byte`, `kb`, `mb`, `gb` and `tb` convert a size to their unit, in steps of 1024.

### To a unit

The value is in bytes.

| Input | Result |
|---|---|
| `gb(0x40000000)` | `1` |
| `mb(0x200000)` | `2` |
| `kb(4096)` | `4` |
| `tb(0x7F0000000000)` | `127` |
| `byte(4096)` | `4096` |
| `kb("A")` | `0.06347` |
| `kb(true)` | `0.00097` |

### From a unit

A unit after the value says what the value is in. It is a bare name or a string, in any letter case, short or spelled out.

| Input | Result |
|---|---|
| `gb(512, mb)` | `0.5` |
| `byte(4, gb)` | `4294967296` |
| `byte(1.5, kb)` | `1536` |
| `kb(1, gb)` | `1048576` |
| `tb(512, gb)` | `0.5` |
| `mb(3, gb)` | `3072` |
| `tb(5, tb)` | `5` |
| `gb(512, :megabyte)` | `0.5` |
| `gb(512, "MiB")` | `0.5` |
| `gb(512, "megabytes")` | `0.5` |
| `byte(1, "GiB")` | `1073741824` |
| `kb(1, "Terabyte")` | `1073741824` |
| `mb(1048576, "b")` | `1` |

### Both units in the name

`A_to_B(x)` is `B(x, A)`, for each pair of `byte`, `kb`, `mb`, `gb` and `tb`.

| Input | Result |
|---|---|
| `mb_to_gb(512)` | `0.5` |
| `gb_to_byte(4)` | `4294967296` |
| `kb_to_mb(1536)` | `1.5` |
| `tb_to_gb(2)` | `2048` |
| `byte_to_kb(1024)` | `1` |
| `gb_to_tb(1)` | `0.00097` |
| `mb_to_kb(3)` | `3072` |
| `byte_to_tb(1)` | `0.0000000000009094947` |
| `gb_to_mb(1, u8)` | `1024` |

### A result that is not whole

When the division leaves a remainder the result is a float: shown to 5 places, cut and not rounded, or to 20 when the first 5 are zeros. A whole result has no fraction.

| Input | Result |
|---|---|
| `kb(1000)` | `0.97656` |
| `kb(1025)` | `1.00097` |
| `mb(0x1234567)` | `18.20444` |
| `gb(1.5e9)` | `1.39698` |
| `kb(1023.999999)` | `0.99999` |
| `mb(1)` | `0.00000095367431640625` |
| `gb(1)` | `0.00000000093132257461` |
| `tb(1)` | `0.0000000000009094947` |
| `gb(0x1000)` | `0.000003814697265625` |
| `kb(-2049.0)` | `-2.00097` |
| `kb(1.0e-30)` | `9.765625e-34` |
| `kb(2048.5 - 0.5)` | `2` |

### In arithmetic

A conversion returns its number, and the result line follows the helper called last.

| Input | Result |
|---|---|
| `gb(byte(1024))` | `0.00000095367431640625` |
| `hex(byte(2, mb))` | `0x200000` |
| `gb(0x40000000) + 1` | `2` |
| `mb(1, gb) * 1.5` | `1536` |
| `bin(kb(4096))` | `0b100` |
| `dec(gb(1, tb))` | `1024` |

### A unit in a base helper

`bin`, `oct`, `dec` and `hex` take a unit too: it says what the value is in, and the value is converted to bytes.

| Input | Result |
|---|---|
| `hex(4, gb)` | `0x100000000` |
| `hex(1, mb)` | `0x100000` |
| `bin(1, kb)` | `0b10000000000` |
| `hex(1.5, kb)` | `0x600` |
| `hex(4, gb, u32)` | `0x0` |
| `hex(1, mb, bin)` | `0b100000000000000000000` |

### With a type

A type among the options converts the value first, as a C cast does, and the constant is then multiplied or divided as C would: the division truncates and the product is cut. Without one an integer is a `u64`.

| Input | Result |
|---|---|
| `gb(0x1000, u64)` | `0` |
| `byte(4, gb, u32)` | `0` |
| `byte(4, tb, u32)` | `4398046511104` |
| `kb(-2048)` | `18014398509481982` |
| `kb(-2048, s64)` | `-2` |
| `kb(-2049, s64)` | `-2` |
| `kb(200, mb, u8)` | `204800` |
| `kb(-1, u32)` | `4194303` |
| `kb(-4096, "int")` | `-4` |
| `gb(1, f32)` | `0.00000000093132257461` |
| `gb(0x1000, f64)` | `0.000003814697265625` |
| `gb(0x1000, big)` | `0.000003814697265625` |
| `gb(1 <<< 70, big)` | `1099511627776` |

### Errors

| Input | Error |
|---|---|
| `gb(1, mb, kb)` | `(ArgumentError) gb takes one unit, got mb and kb` |
| `mb_to_gb(1, kb)` | `(ArgumentError) mb_to_gb takes one unit, got mb and kb` |
| `hex(1, mb, kb)` | `(ArgumentError) hex takes one unit, got mb and kb` |
| `gb(1, hex)` | `(ArgumentError) gb expects options among byte, kb, mb, gb, tb, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got :hex` |
| `gb(1, u16, s8)` | `(ArgumentError) gb takes one type, got u16 and s8` |
| `gb(nil)` | `(ArgumentError) gb expects an integer, float, boolean, or single character, got nil` |
| `gb("AB")` | `(ArgumentError) gb expects a single character, got "AB" (2 code points)` |
| `gb(1, "furlong")` | `(ArgumentError) gb expects options among byte, kb, mb, gb, tb, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got "furlong"` |

## A helper without a value

Called with nothing, a helper returns its name. That is how a bare `u16` or `hex` works as an option.

| Input | Result |
|---|---|
| `hex()` | `:hex` |
| `u16()` | `:u16` |
| `[bin(), oct(), dec(), hex()]` | `[:bin, :oct, :dec, :hex]` |
| `big()` | `:big` |

## Without the REPL's hooks

The single result line needs IEx's `parser` and `inspect_fun` settings. Where one is missing, each helper
prints its own value when it is called and the result line is IEx's usual one:

```text
> bin(hex(5) + 1)
0x5
0b110
6
```
