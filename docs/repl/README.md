# Number-base helpers

`bin`, `oct`, `dec` and `hex` for four REPLs, with numbers that behave as C's do on x86-64 Linux (GCC, LP64):
a value has a width, what does not fit is cut, a negative number is its two's complement pattern, and division
truncates. They are for the arithmetic of binary analysis, reversing and kernel constants.

Each REPL has its own page, with every case it supports and every error it reports:

| REPL | Source | Cases |
|---|---|---|
| irb | `irb/irbrc` | [irb.md](irb.md) |
| IEx | `iex/iex.exs` | [iex.md](iex.md) |
| node | `node/repl.js` | [node.md](node.md) |
| LuaJIT | `luajit/repl.lua` | [luajit.md](luajit.md) |

[cnum.md](cnum.md) covers `cnum`, a calculator of its own written in Racket (`cnum/cnum.rkt`). It has the same
helpers under C's own syntax: a cast is `(unsigned char)x`, a constant takes a suffix (`1u`, `1.5f`), every
operator is C's (`-7 / 2` is -3), and `f(a, b) = a * b` defines a function.

`tests/repl.sh` runs every row of those pages and compares the output, so a page that falls behind the code
fails the checks.

## What all four do

- `bin(x)`, `oct(x)`, `dec(x)` and `hex(x)` return their number, so they nest in arithmetic. The result line
  shows the statement's value once, in the base of the helper called last.
- With no type written, a number is a `u64`.
- A type after the value converts it as a C cast does: `hex(x, u16)`. A base there changes the base:
  `hex(x, bin)`. Options come in any order and letter case.
- The type names are functions that convert, `u16(x)`, beside `cast(type, x)` for any spelling of a type and
  `sizeof` for a type or a value.
- A float keeps its fraction, `true` and `false` are 1 and 0, and a string of one character is its code point.
- A plain number wider than 64 bits is cut to its low 64, with a note on standard error; a type says how much
  to keep, so there is no note then.
- A wrong value or option is an error that names the helper, and the next statement starts clean.

## Sizes

`byte`, `kb`, `mb`, `gb` and `tb` convert a size to their unit, in steps of 1024.

| Input | Meaning |
|---|---|
| `gb(x)` | `x` bytes, in gigabytes |
| `gb(512, mb)` | 512 megabytes, in gigabytes |
| `byte(4, gb)` | 4 gigabytes, in bytes |
| `mb_to_gb(512)` | the same as `gb(512, mb)`; there is one for each pair of units |
| `gb(x, u32)` | computed as C would in that type: the division truncates and the product is cut |

A whole result is shown with no fraction. When the division leaves a remainder the result is a float, shown
to 5 places, or to 20 when the first 5 are zeros. A unit can be spelled out: `"megabyte"`, `"MiB"`.

## The types

The sizes are those of x86-64 Linux, where `char` is signed.

| Name | C type | Bits | Range | Also spelled |
|---|---|---|---|---|
| `u8` | `unsigned char` | 8 | 0 to 255 | `uint8_t` |
| `s8` | `signed char`, `char` | 8 | -128 to 127 | `int8_t` |
| `u16` | `unsigned short` | 16 | 0 to 65535 | `uint16_t`, `ushort` |
| `s16` | `short` | 16 | -32768 to 32767 | `int16_t` |
| `u32` | `unsigned int` | 32 | 0 to 4294967295 | `uint32_t`, `unsigned`, `uint` |
| `s32` | `int` | 32 | -2147483648 to 2147483647 | `int32_t`, `signed` |
| `u64` | `unsigned long` | 64 | 0 to 18446744073709551615 | `uint64_t`, `size_t`, `uintptr_t`, `uintmax_t`, `ulong`, `unsigned long long` |
| `s64` | `long` | 64 | -9223372036854775808 to 9223372036854775807 | `int64_t`, `ssize_t`, `intptr_t`, `ptrdiff_t`, `intmax_t`, `long long` |
| `f32` | `float` | 32 | single precision | `float` |
| `f64` | `double` | 64 | double precision | `double` |
| `big` | none | none | every integer | |

A C name with several words takes them in any order, with or without `int`, as C does: `"unsigned long"`,
`"long unsigned int"`, `"short int"`. `long double` has no counterpart.

## Where the REPLs differ

| | irb | IEx | node | LuaJIT | cnum |
|---|---|---|---|---|---|
| A type as an option | `u16`, `:u16`, `"u16"` | `u16`, `:u16`, `"u16"` | `u16`, `"u16"` | `u16`, `"u16"` | `u16`, `unsigned short` |
| A conversion returns | a typed value | an integer | a number, or a BigInt for 64 bits | a typed value | a typed value |
| Arithmetic on the result | C's rules | Elixir's | JavaScript's | C's rules | C's rules |
| A 64-bit value is written | as any Integer | as any integer | `0x...n` | `0x...ULL` | as any constant, or with `ull` |
| A float to an integer type | as GCC's instruction converts | as GCC's instruction converts | fraction dropped, rest cut | fraction dropped, rest cut | as GCC's instruction converts |
| `big` | yes | yes | yes, a BigInt | no | yes |
| A value is shown for | every statement | every statement | every statement | a line that starts with `=` | every line |
| Bit operations | `& \| ^ ~ << >>` | `band`, `bor`, `bxor`, `bnot`, `<<<`, `>>>` | `& \| ^ ~ << >>`, on 32 bits for a number | `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift` | `& \| ^ ~ << >>` |

In irb and LuaJIT a converted value keeps its type, and arithmetic on it follows C: an operand narrower than
`int` is promoted to `int`, two operands meet in their common type, the result is cut to it, `/` truncates
toward zero, `%` takes the sign of the dividend, and a shift and a comparison follow the sign. A plain number
beside a typed one is typed as a decimal C constant: `s32` when it fits, else `s64`, else `u64`.

IEx and node cannot change what their operators do. A conversion cuts where it is called, and what is computed
from the result afterwards is the language's own arithmetic, until the next conversion.

A node or LuaJIT number is a double: exact up to 2^53, after which a helper says so on standard error.

## Where C leaves the result undefined

C does not define these, so the choice made here is that of GCC's code on x86-64:

| Case | Result |
|---|---|
| A signed result that overflows | wraps, as with `-fwrapv` |
| A shift by a negative count, or by the width or more | the low 5 bits of the count are used for a 32-bit type and the low 6 for a 64-bit one; irb says so on standard error |
| A division or remainder by zero | an error, where the instruction would stop the program |
| The lowest value of a signed type divided by -1 | the lowest value, and a remainder of 0 |
| A float outside the type's range, to an integer type | in irb and IEx the lowest value of the register the instruction converts into; in node and LuaJIT the fraction is dropped and the rest cut |
| A float outside single precision, to `f32` | infinity; IEx has none and reports an error |

A plain number has no type until it meets a typed one or a helper, so `-7 / 2` is the language's own division
and `0xFFFFFFFF` is not the `unsigned int` it is in C. Give the operand a type to compute as C does:
`s32(-7) / 2`, `u32(0xFFFFFFFF)`.

## Without the REPL's hooks, and outside a REPL

Each page ends with what happens when the REPL lacks the hooks the single result line needs (every helper then
prints its own value), and for node and LuaJIT with where the helpers are not defined at all.
