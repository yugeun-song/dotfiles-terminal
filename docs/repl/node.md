# Number-base helpers in node

Every row below was run in node; `tests/repl.sh` runs each one again and compares. The first column is typed
at the prompt and the second is what node printed: the result line is the one node prints after a statement.
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
| `bin(hex(0x10) << 2)` | `0b1000000` |
| `hex(1) + bin(2)` | `0b11` |
| `hex(hex(bin(0x1000) * 64) << 4) - 0x100` | `0x3FFF00` |
| `hex(255) + 1` | `0x100` |
| `1 + hex(255)` | `0x100` |
| `dec(hex(255))` | `255` |
| `hex(dec(255))` | `0xFF` |
| `x = hex(16)` | `0x10` |
| `x` | `16` |
| `x + 1` | `17` |
| `7` | `7` |
| `[hex(1), bin(2)]` | `[ 1, 2 ]` |
| `String(hex(255))` | `'255'` |
| `hex(1); bin(2)` | `0b10` |

## A base as an option

A base name after the value shows the value in that base instead of the helper's own. It is written bare, or
as a constant or a string, in any letter case.

| Input | Result |
|---|---|
| `bin(5, hex)` | `0x5` |
| `hex(5, bin)` | `0b101` |
| `dec(255, oct)` | `0o377` |
| `oct(8, dec)` | `8` |
| `hex(255, "bin")` | `0b11111111` |
| `hex(255, "BIN")` | `0b11111111` |
| `hex(255, " bin ")` | `0b11111111` |
| `hex(5, hex)` | `0x5` |
| `hex(5, bin, bin)` | `0b101` |
| `hex(-1, u8, bin)` | `0b11111111` |
| `hex(-1, bin, u8)` | `0b11111111` |

## With no type: u64

A number with no type written is a `u64`: a BigInt is converted to one, and a number is shown as one but
returned as it is, since a double cannot hold 64 bits. A negative number shows its two's complement pattern.

| Input | Result |
|---|---|
| `hex(0)` | `0x0` |
| `hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `dec(-1)` | `18446744073709551615` |
| `oct(-1)` | `0o1777777777777777777777` |
| `bin(-1)` | `0b1111111111111111111111111111111111111111111111111111111111111111` |
| `dec(-8)` | `18446744073709551608` |
| `hex(~0x1000)` | `0xFFFFFFFFFFFFEFFF` |
| `dec(~0x1000)` | `18446744073709547519` |
| `hex(0xFFFFFFFFFFFFFFFFn)` | `0xFFFFFFFFFFFFFFFFn` |
| `dec(0xFFFFFFFFFFFFFFFFn)` | `18446744073709551615n` |
| `hex(0x8000000000000000n)` | `0x8000000000000000n` |
| `hex(-(1n << 63n))` | `0x8000000000000000n` |
| `dec(-(1n << 63n))` | `9223372036854775808n` |
| `x = hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `x` | `-1` |
| `x = hex(-1n)` | `0xFFFFFFFFFFFFFFFFn` |

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
| `u64` | `0xFFFFFFFFFFFFFF38n` | `18446744073709551416n` | `0o1777777777777777777470n` | `0b1111111111111111111111111111111111111111111111111111111100111000n` |
| `s64` | `0xFFFFFFFFFFFFFF38n` | `-200n` | `0o1777777777777777777470n` | `0b1111111111111111111111111111111111111111111111111111111100111000n` |
| `f32` | `-0xC8` | `-200` | `-0o310` | `-0b11001000` |
| `f64` | `-0xC8` | `-200` | `-0o310` | `-0b11001000` |
| `big` | `-0xC8n` | `-200n` | `-0o310n` | `-0b11001000n` |

| TYPE | `hex(0x123456789, TYPE)` | `dec(0x123456789, TYPE)` | `oct(0x123456789, TYPE)` | `bin(0x123456789, TYPE)` |
|---|---|---|---|---|
| `u8` | `0x89` | `137` | `0o211` | `0b10001001` |
| `s8` | `0x89` | `-119` | `0o211` | `0b10001001` |
| `u16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `s16` | `0x6789` | `26505` | `0o63611` | `0b110011110001001` |
| `u32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `s32` | `0x23456789` | `591751049` | `0o4321263611` | `0b100011010001010110011110001001` |
| `u64` | `0x123456789n` | `4886718345n` | `0o44321263611n` | `0b100100011010001010110011110001001n` |
| `s64` | `0x123456789n` | `4886718345n` | `0o44321263611n` | `0b100100011010001010110011110001001n` |
| `f32` | `0x123456800` | `4886718464` | `0o44321264000` | `0b100100011010001010110100000000000` |
| `f64` | `0x123456789` | `4886718345` | `0o44321263611` | `0b100100011010001010110011110001001` |
| `big` | `0x123456789n` | `4886718345n` | `0o44321263611n` | `0b100100011010001010110011110001001n` |

### Spelling a type

A type is written bare, as a constant or as a string; letter case and the space around it do not matter, and
naming the same type twice is not a conflict.

| Input | Result |
|---|---|
| `hex(-1, u16)` | `0xFFFF` |
| `hex(-1, "u16")` | `0xFFFF` |
| `hex(-1, "U16")` | `0xFFFF` |
| `hex(-1, " u16 ")` | `0xFFFF` |
| `hex(-1, u16, "u16")` | `0xFFFF` |
| `hex(-1, u16, "uint16_t")` | `0xFFFF` |

### C type names

A type can be spelled as C spells it. The sizes are those of x86-64 Linux (LP64): `char` is 8 bits and signed,
`short` 16, `int` 32, `long` and `long long` 64. The words of a multi-word type come in any order, as in C.

| TYPE | `hex(-1, TYPE)` | `dec(-1, TYPE)` | `sizeof(TYPE)` |
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
| `"long"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"long int"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"signed long"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"unsigned long"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"long unsigned int"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"ulong"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"long long"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"long long int"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"unsigned long long"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"int8_t"` | `0xFF` | `-1` | `1` |
| `"uint8_t"` | `0xFF` | `255` | `1` |
| `"int16_t"` | `0xFFFF` | `-1` | `2` |
| `"uint16_t"` | `0xFFFF` | `65535` | `2` |
| `"int32_t"` | `0xFFFFFFFF` | `-1` | `4` |
| `"uint32_t"` | `0xFFFFFFFF` | `4294967295` | `4` |
| `"int64_t"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"uint64_t"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"size_t"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"ssize_t"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"intptr_t"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"uintptr_t"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"ptrdiff_t"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"intmax_t"` | `0xFFFFFFFFFFFFFFFFn` | `-1n` | `8` |
| `"uintmax_t"` | `0xFFFFFFFFFFFFFFFFn` | `18446744073709551615n` | `8` |
| `"float"` | `-0x1` | `-1` | `4` |
| `"double"` | `-0x1` | `-1` | `8` |

## Converting

The type names are functions as well: `u16(x)` is C's `(uint16_t)x`. The result is a number for the types up
to 32 bits and a BigInt for the 64-bit ones and `big`; a BigInt stays a BigInt. A number is a double: its
fraction is dropped and the rest is cut to the type, also where C leaves the conversion undefined.

| TYPE | `TYPE(300)` | `TYPE(-1)` | `TYPE(0x123456789)` | `TYPE(3.9)` | `TYPE(-3.9)` |
|---|---|---|---|---|---|
| `u8` | `44` | `255` | `137` | `3` | `253` |
| `s8` | `44` | `-1` | `-119` | `3` | `-3` |
| `u16` | `300` | `65535` | `26505` | `3` | `65533` |
| `s16` | `300` | `-1` | `26505` | `3` | `-3` |
| `u32` | `300` | `4294967295` | `591751049` | `3` | `4294967293` |
| `s32` | `300` | `-1` | `591751049` | `3` | `-3` |
| `u64` | `300n` | `18446744073709551615n` | `4886718345n` | `3n` | `18446744073709551613n` |
| `s64` | `300n` | `-1n` | `4886718345n` | `3n` | `-3n` |
| `f32` | `300` | `-1` | `4886718464` | `3.9000000953674316` | `-3.9000000953674316` |
| `f64` | `300` | `-1` | `4886718345` | `3.9` | `-3.9` |
| `big` | `300n` | `-1n` | `4886718345n` | `3n` | `-3n` |

| Input | Result |
|---|---|
| `s64(s32(-1))` | `-1n` |
| `u64(s32(-1))` | `18446744073709551615n` |
| `u8(s16(-1))` | `255` |
| `s8(u8(200))` | `-56` |
| `u16(s8(-1))` | `65535` |
| `s16(1e10)` | `-7168` |
| `s32(1e10)` | `1410065408` |
| `u32(1e10)` | `1410065408` |
| `s64(1e20)` | `s64: 100000000000000000000 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`7766279631452241920n` |
| `u64(1e20)` | `u64: 100000000000000000000 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`7766279631452241920n` |
| `u64(-1.5)` | `18446744073709551615n` |
| `s8(-128.9)` | `-128` |
| `u8(255.9)` | `255` |
| `u8(256.0)` | `0` |
| `f32(0.1)` | `0.10000000149011612` |
| `f32(16777217)` | `16777216` |
| `f64(1)` | `1` |
| `f64(u64(-1))` | `18446744073709552000` |
| `f32(u64(-1))` | `18446744073709552000` |
| `f32(1e39)` | `Infinity` |
| `big(3.9)` | `3n` |
| `big(-3.9)` | `-3n` |
| `big(u8(255)) + 1n` | `256n` |

### cast and sizeof

`cast(type, value)` converts to a type under any of its spellings. `sizeof` takes a type or a value and
answers in bytes.

Values carry no type here, so `sizeof` of a number is the size of the constant it would be in C: 4 when it
fits an `int`, else 8, and 8 for a fraction.

| Input | Result |
|---|---|
| `cast("int", 0xFFFFFFFF)` | `-1` |
| `cast("unsigned char", 300)` | `44` |
| `cast(u16, 0x12345)` | `9029` |
| `cast("size_t", -1)` | `18446744073709551615n` |
| `cast("float", 0.1)` | `0.10000000149011612` |
| `cast("double", 1)` | `1` |
| `cast(big, 3.9)` | `3n` |
| `sizeof("int")` | `4` |
| `sizeof(u8)` | `1` |
| `sizeof("unsigned long")` | `8` |
| `sizeof(f32)` | `4` |
| `sizeof(u8(1))` | `4` |
| `sizeof(u8(1) + u8(1))` | `4` |
| `sizeof(5)` | `4` |
| `sizeof(2 ** 40)` | `8` |
| `sizeof(1.5)` | `8` |
| `sizeof("int") - 5` | `-1` |

## Arithmetic

node cannot change what its operators do, so arithmetic is JavaScript's own. A number is a double: exact up to
2^53, with bit operations on 32 bits. A BigInt has no width and never wraps; its `/` and `%` truncate as C's
do. A conversion cuts where it is called and no further.

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
| `-7n / 2n` | `-3n` |
| `-7n % 2n` | `-1n` |
| `7n / -2n` | `-3n` |
| `7n % -2n` | `1n` |
| `-8 >> 1` | `-4` |
| `-8 >>> 1` | `2147483644` |
| `u64(-8) >> 1n` | `9223372036854775804n` |
| `hex(-1n) >> 4n` | `0xFFFFFFFFFFFFFFFn` |
| `hex(-1n, s64) >> 4n` | `0xFFFFFFFFFFFFFFFFn` |
| `~0` | `-1` |
| `hex(~0)` | `0xFFFFFFFFFFFFFFFF` |
| `1 << 31` | `-2147483648` |
| `hex(1 << 31)` | `0xFFFFFFFF80000000` |
| `hex(1 << 32)` | `0x1` |
| `hex(1n << 32n)` | `0x100000000n` |
| `s32(-1) < u32(1)` | `true` |
| `hex(0xFF00FF00 & 0xFFFF)` | `0xFF00` |
| `hex(0xFFFFFFFF \| 0)` | `0xFFFFFFFFFFFFFFFF` |
| `typeof hex(5)` | `'number'` |
| `typeof hex(5, u32)` | `'number'` |
| `typeof hex(5, u64)` | `'bigint'` |
| `typeof hex(5n)` | `'bigint'` |
| `hex(5, u64) + 1n` | `0x6n` |
| `2 ** 53 + 1` | `9007199254740992` |

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
| `hex(-0.0)` | `0x0` |
| `hex(255.0)` | `0xFF` |
| `hex(2.5) * 2` | `0x5` |
| `hex(1.5, f32)` | `0x1.8` |
| `hex(0.1, f32)` | `0x0.199999A` |
| `hex(0.1, f64)` | `0x0.1999999999999A` |
| `dec(0.1, f32)` | `0.10000000149011612` |
| `hex(255, f32)` | `0xFF` |
| `hex(1.5, u8)` | `0x1` |
| `hex(-1.5, u8)` | `0xFF` |
| `hex(1.5, big)` | `0x1n` |
| `hex(1e39, f32)` | `Infinity` |

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
| `hex(255n)` | `0xFFn` |
| `hex(new Number(255))` | `0xFF` |
| `hex(new String("A"))` | `0x41` |
| `hex(Object(255n))` | `0xFFn` |

## Notes on standard error

A BigInt wider than 64 bits with no type is cut to its low 64, with a note. A number past 2^53 is no longer
exact, and a helper says so once in a statement.

| Input | Result |
|---|---|
| `hex(1n << 64n)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`<br>`0x0n` |
| `hex((1n << 64n) + 5n)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`<br>`0x5n` |
| `dec(-(1n << 64n))` | `dec: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`<br>`0n` |
| `hex(1n << 64n, big)` | `0x10000000000000000n` |
| `hex(1n << 64n, u64)` | `0x0n` |
| `hex(2 ** 53)` | `hex: 9007199254740992 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`0x20000000000000` |
| `hex(2 ** 53 - 1)` | `0x1FFFFFFFFFFFFF` |
| `hex(0xffffffff81001234)` | `hex: 18446744071578850000 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`0xFFFFFFFF81001000` |
| `hex(0xffffffff81001234n)` | `0xFFFFFFFF81001234n` |
| `hex(2 ** 64)` | `hex: 18446744073709552000 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`hex: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`<br>`0x0` |
| `u64(2 ** 64)` | `u64: 18446744073709552000 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`0n` |
| `hex(2 ** 70, big)` | `hex: 1.1805916207174113e+21 is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`<br>`0x400000000000000000n` |

## Errors

A statement that fails prints no result line, and the next statement starts clean. node prints `Uncaught`
before the message and a stack trace after it.

### Values

| Input | Error |
|---|---|
| `hex(null)` | `TypeError: hex() expects a number, bigint, boolean, or single character, got null` |
| `hex(undefined)` | `TypeError: hex() expects a number, bigint, boolean, or single character, got undefined` |
| `hex()` | `TypeError: hex() expects a number, bigint, boolean, or single character, got undefined` |
| `hex("AB")` | `TypeError: hex() expects a single character, got 'AB' (2 code points)` |
| `hex("")` | `TypeError: hex() expects a single character, got '' (0 code points)` |
| `hex([1])` | `TypeError: hex() expects a number, bigint, boolean, or single character, got [ 1 ]` |
| `hex({})` | `TypeError: hex() expects a number, bigint, boolean, or single character, got {}` |
| `hex(Symbol())` | `TypeError: hex() expects a number, bigint, boolean, or single character, got Symbol()` |
| `hex(NaN)` | `RangeError: hex() expects a finite number, got NaN` |
| `hex(Infinity)` | `RangeError: hex() expects a finite number, got Infinity` |
| `hex("\uD800")` | `TypeError: hex() expects a well-formed character, got '\ud800'` |
| `u8("AB")` | `TypeError: u8() expects a single character, got 'AB' (2 code points)` |
| `u8(null)` | `TypeError: u8() expects a number, bigint, boolean, or single character, got null` |
| `f32(NaN)` | `RangeError: f32() expects a finite number, got NaN` |

### Options

| Input | Error |
|---|---|
| `hex(1, "foo")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'foo'` |
| `hex(1, 16)` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 16` |
| `hex(1, null)` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got null` |
| `hex(1, "u128")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'u128'` |
| `hex(1, "long long long")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'long long long'` |
| `hex(1, "unsigned signed")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'unsigned signed'` |
| `hex(1, "char int")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'char int'` |
| `hex(1, "short long")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'short long'` |
| `hex(1, "long double")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'long double'` |
| `hex(1, "")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got ''` |
| `hex(1, "int int")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'int int'` |
| `hex(1, u8, u16)` | `TypeError: hex() takes one type, got u8 and u16` |
| `hex(1, bin, oct)` | `TypeError: hex() takes one base, got bin and oct` |
| `hex(1, "int", "long")` | `TypeError: hex() takes one type, got s32 and s64` |
| `hex(1, u8, bin, s8)` | `TypeError: hex() takes one type, got u8 and s8` |
| `hex(1, "__proto__")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got '__proto__'` |
| `hex(1, "constructor")` | `TypeError: hex() expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'constructor'` |

### The type functions, cast and sizeof

| Input | Error |
|---|---|
| `u8(1, 2)` | `TypeError: u8() takes one value, got 2` |
| `cast(hex, 1)` | `TypeError: cast() expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got [Function: hex]` |
| `cast("foo", 1)` | `TypeError: cast() expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'foo'` |
| `cast("int")` | `TypeError: cast() expects a number, bigint, boolean, or single character, got undefined` |
| `cast("int", "AB")` | `TypeError: cast() expects a single character, got 'AB' (2 code points)` |
| `sizeof(big)` | `TypeError: sizeof() expects a type with a size, got big` |
| `sizeof(null)` | `TypeError: sizeof() expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got null` |
| `sizeof("foo")` | `TypeError: sizeof() expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 'foo'` |
| `sizeof(hex)` | `TypeError: sizeof() expects a type among u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got [Function: hex]` |

## A helper without a value

A bare name is the function itself, which is how `u16` or `hex` works as an option.

| Input | Result |
|---|---|
| `typeof hex` | `'function'` |
| `hex.name` | `'hex'` |
| `typeof u16` | `'function'` |
| `typeof cast` | `'function'` |

## Without the REPL's hooks

The single result line needs the REPL's `eval` and `writer` functions. Where one is missing, each helper
prints its own value when it is called and the result line is node's usual one:

```text
> bin(hex(5) + 1)
0x5
0b110
6
```

## Outside an interactive REPL

`NODE_OPTIONS` loads the file into every node, but it defines nothing unless node starts an interactive REPL
on the main thread: not under `-e`, `-p`, `--check`, a script or a worker.

```text
$ node -p 'typeof hex'
undefined
```
