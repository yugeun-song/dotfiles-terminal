# cnum

A calculator of its own, written in Racket: C's expression syntax on top, s-expressions underneath, and numbers
that behave as GCC's do on x86-64 Linux (LP64). `cnum` starts a prompt, `cnum 'hex(4, gb)'` evaluates its
arguments, and lines on standard input are evaluated one by one. Source: `cnum/cnum.rkt`.

Unlike the helpers of the other four REPLs, nothing here belongs to a host language: the constants, the
operators and their precedence, casts, suffixes and every helper are rules of this one file. `tests/repl.sh`
runs every row below, top to bottom in one session.

## The result line

Every statement shows its value. `bin`, `oct`, `dec` and `hex` return their number, and the line shows the statement's value once, in the base of the helper called last. Statements on one line are separated by `;`, and the last one is shown.

| Input | Result |
|---|---|
| `255` | `255` |
| `hex(255)` | `0xFF` |
| `bin(hex(0x10) << 2)` | `0b1000000` |
| `hex(1) + bin(2)` | `0b11` |
| `x = hex(16)` | `0x10` |
| `x` | `16` |
| `hex(5, bin)` | `0b101` |
| `1; 2; hex(3)` | `0x3` |

## Constants

A constant written without a suffix has no type yet: it is exact, however large, until it meets a typed value, which types it as C types a decimal constant (`int` when it fits, else `long`, else `unsigned long`). Division truncates and `%` takes the sign of the dividend, as in C. With no type written, a helper takes a constant as a `u64`.

| Input | Result |
|---|---|
| `0x1000 * 4` | `16384` |
| `-7 / 2` | `-3` |
| `-7 % 2` | `-1` |
| `10 / 4` | `2` |
| `10 / 4.0` | `2.5` |
| `1 << 40` | `1099511627776` |
| `1 << 100` | `1267650600228229401496703205376` |
| `hex(1 << 100, big)` | `0x10000000000000000000000000` |
| `0755` | `493` |
| `0o755` | `493` |
| `0b1010` | `10` |
| `'A'` | `65` |
| `'\n'` | `10` |
| `'\x41'` | `65` |
| `1.5` | `1.5` |
| `1e3` | `1000.0` |
| `.5` | `0.5` |
| `0xFFFFFFFF + 1` | `4294967296` |
| `~0xFFF` | `-4096` |
| `hex(~0xFFF)` | `0xFFFFFFFFFFFFF000` |
| `hex(-1)` | `0xFFFFFFFFFFFFFFFF` |
| `dec(-1)` | `18446744073709551615` |
| `dec(-1, s64)` | `-1` |
| `true + true` | `2` |

## Suffixes

A suffix types a constant as C does: `u`, `l`, `ul`, `ll`, `ull` in either case, and `f` for a float.

| Input | Result |
|---|---|
| `0xFFFFFFFFu + 1` | `0` |
| `1u - 2` | `4294967295` |
| `1L << 40` | `1099511627776` |
| `-1ull` | `18446744073709551615` |
| `2147483648u` | `2147483648` |
| `sizeof(1)` | `4` |
| `sizeof(2147483648)` | `8` |
| `sizeof(1u)` | `4` |
| `sizeof(1L)` | `8` |
| `sizeof(1ull)` | `8` |
| `sizeof(1.5)` | `8` |
| `sizeof(1.5f)` | `4` |
| `0.1f` | `0.10000000149011612` |
| `0.1f + 0.2f` | `0.30000001192092896` |
| `0.1 + 0.2` | `0.30000000000000004` |
| `0.1f + 0.2` | `0.30000000149011613` |

## Types and casts

The types are `u8` to `u64`, `s8` to `s64`, `f32`, `f64` and `big` (no width), and every C spelling of them: `unsigned long`, `signed char`, `uint32_t`, `size_t` and so on, with the sizes of x86-64 Linux. A cast is written as in C or as a call.

| Input | Result |
|---|---|
| `(u8)300` | `44` |
| `u8(300)` | `44` |
| `(unsigned char)300` | `44` |
| `(int8_t)200` | `-56` |
| `(unsigned long)-1` | `18446744073709551615` |
| `(long unsigned int)-1` | `18446744073709551615` |
| `cast(u16, 0x12345)` | `9029` |
| `cast(size_t, -1)` | `18446744073709551615` |
| `(int)3.9` | `3` |
| `(int)-3.9` | `-3` |
| `(int)1e10` | `-2147483648` |
| `(u64)1e19` | `10000000000000000000` |
| `(float)16777217` | `16777216.0` |
| `(double)1` | `1.0` |
| `(big)3.9` | `3` |
| `(short)(char)200` | `-56` |
| `hex(-1, s16)` | `0xFFFF` |
| `dec(0xFFFF, s16)` | `-1` |
| `hex(0x12345, u16)` | `0x2345` |
| `hex(-1, unsigned long)` | `0xFFFFFFFFFFFFFFFF` |
| `dec(200, signed char)` | `-56` |
| `hex(-1, int)` | `0xFFFFFFFF` |
| `hex(-255, big)` | `-0xFF` |
| `hex(255, HEX)` | `0xFF` |
| `hex(-1, U16)` | `0xFFFF` |
| `hex(-1, Size_T)` | `0xFFFFFFFFFFFFFFFF` |
| `hex(-1, bin, u8)` | `0b11111111` |
| `sizeof(int)` | `4` |
| `sizeof(unsigned long)` | `8` |
| `sizeof(char)` | `1` |
| `sizeof(double)` | `8` |
| `sizeof(u8(1))` | `1` |
| `sizeof(u8(1) + u8(1))` | `4` |
| `sizeof x` | `8` |
| `sizeof(int) - 5` | `18446744073709551615` |

## Arithmetic

Typed values compute by C's rules: an operand narrower than `int` is promoted, two operands meet in their common type, the result is cut to it, and a shift and a comparison follow the sign. A test answers with the `int` 1 or 0. `?:` gives the chosen operand as it is and does not evaluate the other.

| Input | Result |
|---|---|
| `u32(0xFFFFFFFF) + 1` | `0` |
| `s32(0x7FFFFFFF) + 1` | `-2147483648` |
| `u8(250) + u8(10)` | `260` |
| `s8(-128) - 1` | `-129` |
| `u32(5) - 6` | `4294967295` |
| `s32(-7) / 2` | `-3` |
| `s32(-7) % 2` | `-1` |
| `s32(-2147483648) / -1` | `-2147483648` |
| `s32(-1) < u32(1)` | `0` |
| `s64(-1) < u32(1)` | `1` |
| `hex(u64(-1) >> 60)` | `0xF` |
| `hex(s64(-1) >> 60)` | `0xFFFFFFFFFFFFFFFF` |
| `u32(1) << 31` | `2147483648` |
| `-u32(1)` | `4294967295` |
| `~u64(0)` | `18446744073709551615` |
| `hex(~u8(0))` | `0xFFFFFFFF` |
| `u64(-1) + 1` | `0` |
| `u8(0xF0) & 0x3C` | `48` |
| `u8(0xF0) \| 0x0F` | `255` |
| `u8(0xF0) ^ 0xFF` | `15` |
| `5 > 3` | `1` |
| `5 > 3 && 2 > 3` | `0` |
| `0 \|\| 7` | `1` |
| `!0` | `1` |
| `!5` | `0` |
| `3 ? 10 : 20` | `10` |
| `0 ? 1 / 0 : 20` | `20` |
| `(1 < 2) + (2 < 3)` | `2` |
| `sizeof(1 < 2)` | `4` |

## Floats

A float keeps its fraction, in any base. `f32` arithmetic is single precision unless a double takes part, and an integer beside a float is converted to it first.

| Input | Result |
|---|---|
| `hex(1.5)` | `0x1.8` |
| `bin(0.75)` | `0b0.11` |
| `oct(0.5)` | `0o0.4` |
| `hex(0.1, f32)` | `0x0.199999A` |
| `f32(16777217)` | `16777216.0` |
| `f32(0.1) + f32(0.2)` | `0.30000001192092896` |
| `1.5f * 3` | `4.5` |
| `1 / 3.0` | `0.3333333333333333` |
| `1 / 3.0f` | `0.3333333432674408` |
| `16777217 == 16777217.0f` | `1` |
| `1.0 / 0` | `inf` |
| `-1.0 / 0` | `-inf` |
| `0.0 / 0` | `nan` |
| `1e308 * 10` | `inf` |
| `u8(3.9)` | `3` |
| `s32(1e10)` | `-2147483648` |
| `(int)(0.1f + 0.2f == 0.3f)` | `1` |

## Variables and functions

`name = value` keeps a value with its type, and the compound assignments and `++`, `--` work on it. `name(a, b) = expression` defines a function; it may call itself. The names of the language (helpers, types, units) cannot be reused. Lines in `~/.config/cnum/init` run at the start, for constants and functions of your own.

| Input | Result |
|---|---|
| `n = 5` | `5` |
| `n += 3` | `8` |
| `n++` | `8` |
| `n` | `9` |
| `--n` | `8` |
| `n <<= 4` | `128` |
| `n = u8(250)` | `250` |
| `n += 10` | `260` |
| `PAGE_SHIFT = 12` | `12` |
| `PAGE_SIZE = 1 << PAGE_SHIFT` | `4096` |
| `hex(PAGE_SIZE)` | `0x1000` |
| `PAGE_MASK = ~(PAGE_SIZE - 1); hex(PAGE_MASK)` | `0xFFFFFFFFFFFFF000` |
| `align(v, a) = (v + a - 1) & ~(a - 1)` | `` |
| `hex(align(0x1234, PAGE_SIZE))` | `0x2000` |
| `hex(align(0x1234, PAGE_SIZE), u16)` | `0x2000` |
| `fact(k) = k <= 1 ? 1 : k * fact(k - 1)` | `` |
| `fact(20)` | `2432902008176640000` |
| `fact(25)` | `15511210043330985984000000` |
| `u32(fact(25))` | `2076180480` |
| `pages(bytes) = kb(bytes) / 4` | `` |
| `pages(0x10000)` | `16` |

## Sizes

`byte`, `kb`, `mb`, `gb` and `tb` convert a size to their unit, in steps of 1024. The value is in bytes unless a unit follows it, and `A_to_B(x)` names both. A whole result has no fraction; when the division leaves a remainder the result is a double, shown to 5 places, cut and not rounded, or to 20 when the first 5 are zeros. A type among the options converts the value first and computes as C would: the division truncates and the product is cut.

| Input | Result |
|---|---|
| `gb(0x40000000)` | `1` |
| `kb(4096)` | `4` |
| `tb(0x7F0000000000)` | `127` |
| `gb(512, mb)` | `0.5` |
| `byte(4, gb)` | `4294967296` |
| `byte(1.5, kb)` | `1536` |
| `gb(512, MiB)` | `0.5` |
| `gb(512, megabytes)` | `0.5` |
| `mb_to_gb(512)` | `0.5` |
| `gb_to_byte(4)` | `4294967296` |
| `kb(1000)` | `0.97656` |
| `kb(1023.999999)` | `0.99999` |
| `mb(0x1234567)` | `18.20444` |
| `gb(1)` | `0.00000000093132257461` |
| `gb(0x1000)` | `0.000003814697265625` |
| `kb(-2049.0)` | `-2.00097` |
| `gb(byte(1024))` | `0.00000095367431640625` |
| `hex(byte(2, mb))` | `0x200000` |
| `gb(0x40000000) + 1` | `2` |
| `gb(0x1000, u64)` | `0` |
| `byte(4, gb, u32)` | `0` |
| `byte(4, tb, u32)` | `4398046511104` |
| `kb(-2048)` | `18014398509481982` |
| `kb(-2048, s64)` | `-2` |
| `kb(-2049, s64)` | `-2` |
| `kb(200, mb, u8)` | `204800` |
| `kb(-4096, int)` | `-4` |
| `gb(1, f32)` | `0.00000000093132257461` |
| `gb(0x1000, big)` | `0.000003814697265625` |
| `gb(u64(0x1000))` | `0.000003814697265625` |
| `byte(u32(4), gb)` | `0` |
| `kb(s32(-4096))` | `-4` |
| `kb(s32(-4097))` | `-4.00097` |

## A unit in a base helper

`bin`, `oct`, `dec` and `hex` take a unit too: it says what the value is in, and the value is converted to bytes.

| Input | Result |
|---|---|
| `hex(4, gb)` | `0x100000000` |
| `hex(1, mb)` | `0x100000` |
| `bin(1, kb)` | `0b10000000000` |
| `hex(1.5, kb)` | `0x600` |
| `hex(4, gb, u32)` | `0x0` |
| `hex(1, mb, bin)` | `0b100000000000000000000` |

## The s-expression behind a line

`:ast` shows what a line is read as. The reader produces this tree and the rules in `cnum/cnum.rkt` evaluate it.

| Input | Result |
|---|---|
| `:ast 1 + 2 * 3` | `(binary + 1 (binary * 2 3))` |
| `:ast hex((u8)x << 2, bin)` | `(call hex (binary << (cast u8 (var x)) 2) (var bin))` |
| `:ast f(a) = a ? 1 : 2` | `(define f (a) (if (var a) 1 2))` |
| `:ast n += 1; n++` | `(assign += n 1)`<br>`(step ++ n #f)` |

## Notes on standard error

Where C leaves a shift undefined the x86-64 instruction decides, with a note. A constant wider than 64 bits is cut by a helper that has no type to go by.

| Input | Result |
|---|---|
| `hex(1 << 64)` | `hex: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`<br>`0x0` |
| `u64(1) << 64` | `u64: a shift by 64 is undefined in C; x86-64 uses the low 6 bits of the count`<br>`1` |
| `u8(1) << 40` | `s32: a shift by 40 is undefined in C; x86-64 uses the low 5 bits of the count`<br>`256` |
| `u32(1) << -1` | `u32: a shift by -1 is undefined in C; x86-64 uses the low 5 bits of the count`<br>`2147483648` |

## Errors

An error is one line on standard error, and the next line starts clean.

| Input | Error |
|---|---|
| `7 / 0` | `error: division by zero` |
| `u32(7) % 0` | `error: division by zero` |
| `foo` | `error: foo is not defined` |
| `foo(1)` | `error: foo is not defined` |
| `hex` | `error: hex is not a value here; call it or pass it as an option` |
| `hex()` | `error: hex expects a value` |
| `hex(1, 2)` | `error: hex expects options among bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got 2` |
| `hex(1, u8, u16)` | `error: hex takes one type, got u8 and u16` |
| `hex(1, bin, oct)` | `error: hex takes one base, got bin and oct` |
| `hex(int)` | `error: hex expects a number, got the type int` |
| `gb(1, mb, kb)` | `error: gb takes one unit, got mb and kb` |
| `mb_to_gb(1, kb)` | `error: mb_to_gb takes one unit, got mb and kb` |
| `hex(1, mb, kb)` | `error: hex takes one unit, got mb and kb` |
| `gb(1, hex)` | `error: gb expects options among byte, kb, mb, gb, tb, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, big or a C type name, got hex` |
| `(long double)1` | `error: long double is not a type` |
| `(unsigned float)1` | `error: unsigned float is not a type` |
| `cast(1, 2)` | `error: cast expects a type and a value: cast(u16, x)` |
| `1.5 % 2` | `error: % takes integers, got a double` |
| `~1.5` | `error: ~ takes an integer, got a float` |
| `1.5 << 1` | `error: << takes integers, got a double` |
| `08` | `error: invalid digit in the octal constant 08` |
| `1x` | `error: 1x is not a number` |
| `1uu` | `error: uu is not an integer suffix` |
| `'ab'` | `error: a character constant holds one character, got 'ab'` |
| `5 = 3` | `error: only a variable can be assigned to` |
| `hex = 3` | `error: hex is part of the language; choose another name` |
| `int = 3` | `error: expected (, got =` |
| `gb(a) = a` | `error: gb is part of the language; choose another name` |
| `fact(1, 2)` | `error: fact takes 1 value, got 2` |
| `fact = 3; fact(1)` | `error: fact is not a function` |
| `loop(k) = loop(k + 1); loop(0)` | `error: loop calls itself more than 2000 deep` |
| `1 +` | `error: the line ends where a value is expected` |
| `(1` | `error: expected ), got the end of the line` |
| `1 2` | `error: unexpected 2` |
| `1 << 100000` | `error: a constant shifts by 0 to 65536 places, got 100000` |
| `u32(1) + (1 << 64)` | `error: 18446744073709551616 is wider than 64 bits, so it has no C type; convert it with u64 or another type` |
| `(big)(1e308 * 10)` | `error: big cannot hold inf` |
| `$` | `error: unexpected $` |
