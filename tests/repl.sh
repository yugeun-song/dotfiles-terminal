#!/usr/bin/env bash
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-repl.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/home" "$WORK/plain" "$WORK/run" "$WORK/cwd" "$WORK/bin" "$WORK/with/.config/luajit"
cp -- "$REPO/irb/irbrc" "$WORK/home/.irbrc"
cp -- "$REPO/cnum/cnum.rkt" "$REPO/irb/irbrc" "$REPO/iex/iex.exs" "$REPO/node/repl.js" "$REPO/luajit/repl.lua" "$WORK/"
cp -- "$REPO/luajit/repl.lua" "$WORK/with/.config/luajit/repl.lua"

passed=0
failed=0
HOME_DIR=$WORK/home
ASK=() WANT=()

t() {
    ASK+=("$1")
    WANT+=("$2")
}

is() {
    if [[ $2 == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  repl: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}

clean() { (cd "$WORK/cwd" && env -i PATH="$PATH" HOME="$HOME_DIR" XDG_RUNTIME_DIR="$WORK/run" TERM=dumb LANG=C.UTF-8 "$@" 2>&1); }

session() {
    local name=$1 strip=$2 mark=$3 input i ok
    local -a got=()
    shift 3
    input=$mark$'\n'
    for i in "${!ASK[@]}"; do input+=${ASK[i]}$'\n'$mark$'\n'; done
    mapfile -t got < <(printf '%s' "$input" | clean "$@" | sed -E "$strip" | awk '
        $0 == "@@@" { if (seen++) print rec; rec = ""; skip = 1; next }
        $0 == "" || (skip && $0 == "undefined") { skip = 0; next }
        { skip = 0; rec = (rec == "" ? $0 : rec " | " $0) }')
    for i in "${!ASK[@]}"; do
        ok=0
        if [[ ${WANT[i]} == "~"* ]]; then
            [[ ${got[i]-} =~ ${WANT[i]#\~} ]] && ok=1
        elif [[ ${WANT[i]} == "*"* ]]; then
            [[ ${got[i]-} == *"${WANT[i]#\*}"* ]] && ok=1
        elif [[ ${got[i]-} == "${WANT[i]}" ]]; then
            ok=1
        fi
        if ((ok)); then
            passed=$((passed + 1))
            continue
        fi
        failed=$((failed + 1))
        printf 'FAIL  repl: %s: %s: got [%s], want [%s]\n' "$name" "${ASK[i]}" "${got[i]-}" "${WANT[i]}"
    done
    ASK=() WANT=()
}

documented() {
    local ask want
    while IFS=$'\037' read -r ask want; do t "$ask" "$want"; done < <(awk '
        function spans(text, list,    count) {
            count = 0
            while (match(text, /`[^`]*`/)) {
                list[++count] = substr(text, RSTART + 1, RLENGTH - 2)
                gsub(/\\\|/, "|", list[count])
                text = substr(text, RSTART + RLENGTH)
            }
            return count
        }
        /^\| Input \| (Result|Error) \|$/ { mode = $4; next }
        /^\| TYPE \| / { mode = "matrix"; spans($0, header); next }
        /^\|-/ { next }
        !/^\| / { mode = ""; next }
        mode == "matrix" {
            count = spans($0, cell)
            for (i = 2; i <= count; i++) {
                ask = header[i - 1]
                gsub(/TYPE/, cell[1], ask)
                print ask "\037" cell[i]
            }
            next
        }
        mode {
            count = spans($0, cell)
            want = ""
            for (i = 2; i <= count; i++) want = want (i > 2 ? " | " : "") cell[i]
            print cell[1] "\037" (mode == "Error" ? "*" : "") want
        }' "$REPO/docs/repl/$1.md")
}

WIDE='hex: the value is wider than 64 bits and was cut to the low 64'
NAMES='bin, oct, dec, hex, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64'
EACH='0x5 | 0b110 | 6'

irb_session() { session "$1" 's/^$//' 'puts "@@@";' timeout 120 irb --noverbose; }
iex_session() { session "$1" 's/^((iex|\.\.\.)\([0-9]+\)> )+//' 'IO.puts("@@@"); IEx.dont_display_result()' timeout 120 iex --dot-iex "$2"; }
node_session() { session "$1" 's/^(> |\.\.\. )+//' 'console.log("@@@")' NODE_REPL_HISTORY= NODE_OPTIONS="$2" timeout 120 node -i; }
cnum_session() { session "$1" 's/^error: unexpected @$/@@@/' '@@@' timeout 120 racket "$WORK/cnum.rkt"; }
luajit_session() { session "$1" 's/^(>> |> )+//' 'io.write("@@@\n")' LUA_INIT="$2" timeout 120 luajit -i; }

if command -v irb >/dev/null 2>&1; then
    t 'hex(255)' '0xFF'
    t 'hex(hex(bin(0x1000) * 64) << 4) - 0x100' '0x3FFF00'
    t 'bin(hex(0x10) << 2)' '0b1000000'
    t 'hex(1) + bin(2)' '0b11'
    t 'oct(8)' '0o10'
    t 'hex(~0x1000)' '0xFFFFFFFFFFFFEFFF'
    t 'dec(~0x1000)' '18446744073709547519'
    t 'dec(~0x1000, :s64)' '-4097'
    t 'hex(-1, u16)' '0xFFFF'
    t 'hex(0x12345, "U16")' '0x2345'
    t 'bin(0x1000, hex)' '0x1000'
    t 'u8(300) + s8(200)' '-12'
    t 'u32(0xFFFFFFFF) + 1' '0'
    t 's32(-7) / 2' '-3'
    t 's32(-7) % 2' '-1'
    t 'u8(250) + u8(10)' '260'
    t 's32(-1) < u32(1)' 'false'
    t 'hex(u64(-1) >> 60)' '0xF'
    t 'hex(s64(-1) >> 60)' '0xFFFFFFFFFFFFFFFF'
    t 'hex(0xFFFF, u16) + 1' '0x10000'
    t '2 ** u8(3)' '8'
    t 's32(1e10)' '-2147483648'
    t 'hex(-1, :int)' '0xFFFFFFFF'
    t 'dec(200, "signed char")' '-56'
    t 'cast("unsigned long", -1)' '18446744073709551615'
    t 'sizeof(:int) - 5' '18446744073709551615'
    t 'u64(1) << 64' '~^u64: a shift by 64 is undefined in C; x86-64 uses the low 6 bits of the count \| 1$'
    t 'u32(7) / 0' '~divided by 0 \(ZeroDivisionError\)'
    t 'hex(1.5)' '0x1.8'
    t 'hex(0.1, f32)' '0x0.199999A'
    t 'hex(-0.0)' '-0x0'
    t 'hex("A")' '0x41'
    t 'hex(1 << 64)' "$WIDE; pass :big to keep all of it | 0x0"
    t 'hex(1 << 64, :big)' '0x10000000000000000'
    t 'hex(-255, big)' '-0xFF'
    t 'x = hex(0x12345, u16)' '0x2345'
    t 'x' '9029'
    t 'x >> 4' '564'
    t '[hex(1), bin(2)]' '[1, 2]'
    t 'hex("AB")' '~hex expects a single character, got "AB" \(2 code points\) \(ArgumentError\)'
    t '7' '7'
    t 'hex(1, :foo)' "~hex expects options among $NAMES, big or a C type name, got :foo"
    t 'hex(1, "long long long")' '~or a C type name, got "long long long"'
    t 'hex(1, :u8, :u16)' '~hex takes one type, got u8 and u16'
    t 'hex(nil)' '~hex expects an integer, float, boolean, or single character, got nil'
    t 'hex(Float::NAN)' '~hex expects a finite number, got NaN \(RangeError\)'
    t 'hex(1, BasicObject.new)' '~hex expects options among'
    t 'gb(512, mb)' '0.5'
    t 'hex(byte(2, mb))' '0x200000'
    t 'gb(byte(1024))' '0.00000095367431640625'
    t 'kb(-2049, s64)' '-2'
    t 'x = mb_to_kb(3); x + 1' '3073'
    irb_session irb
    documented irb
    irb_session 'irb, as documented'
    while IFS=$'\037' read -r ask want; do t "$ask" "$want"; done < <(awk '
        match($0, /^ *#   /) && index($0, " # => ") {
            line = substr($0, RLENGTH + 1)
            at = index(line, " # => ")
            ask = substr(line, 1, at - 1)
            sub(/ +$/, "", ask)
            print ask "\037" substr(line, at + 6)
        }' "$REPO/irb/irbrc")
    irb_session 'irb, as its comments say'

    HOME_DIR=$WORK/plain
    printf '%s\n' 'class << IRB::Context' '  def method_defined?(*)' '    false' '  end' 'end' "load '$WORK/irbrc'" \
        'class << IRB::Context' '  remove_method :method_defined?' 'end' >"$WORK/plain/.irbrc"
    t 'bin(hex(5) + 1)' "$EACH"
    irb_session 'irb without its hooks'
    HOME_DIR=$WORK/home
else
    echo "SKIP  repl: irb is not installed"
fi

if command -v iex >/dev/null 2>&1; then
    t 'hex(255)' '0xFF'
    t 'hex(hex(bin(0x1000) * 64) <<< 4) - 0x100' '0x3FFF00'
    t 'bin(hex(0x10) <<< 2)' '0b1000000'
    t 'hex(1) + bin(2)' '0b11'
    t 'hex(255) |> bin()' '0b11111111'
    t 'hex(bnot(0x1000))' '0xFFFFFFFFFFFFEFFF'
    t 'dec(bnot(0x1000), :s64)' '-4097'
    t 'hex(-1, u16)' '0xFFFF'
    t 'hex(0x12345, "U16")' '0x2345'
    t 'bin(0x1000, hex)' '0x1000'
    t 'u8(300) + s8(200)' '-12'
    t 'hex(-1) >>> 4' '0xFFFFFFFFFFFFFFF'
    t 's32(1.0e10)' '-2147483648'
    t 'hex(-1, :int)' '0xFFFFFFFF'
    t 'dec(200, "signed char")' '-56'
    t 'cast("unsigned long", -1)' '18446744073709551615'
    t 'sizeof(:int)' '4'
    t 'hex(1.5)' '0x1.8'
    t 'hex(0.1, :f32)' '0x0.199999A'
    t 'hex(-0.0)' '-0x0'
    t 'hex("A")' '0x41'
    t 'hex(~c"A")' '0x41'
    t 'hex(1 <<< 64)' "$WIDE; pass :big to keep all of it | 0x0"
    t 'hex(1 <<< 64, :big)' '0x10000000000000000'
    t 'x = hex(0x12345, u16)' '0x2345'
    t 'x' '9029'
    t '[hex(1), bin(2)]' '[1, 2]'
    t 'hex("AB")' '~\(ArgumentError\) hex expects a single character, got "AB" \(2 code points\)'
    t '7' '7'
    t 'hex(1, :foo)' "~hex expects options among $NAMES, big or a C type name, got :foo"
    t 'hex(1, :u8, :u16)' '~hex takes one type, got u8 and u16'
    t 'hex(<<255>>)' '~hex expects valid UTF-8, got <<255>>'
    t 'f32(1.0e39)' '~f32 cannot hold 1.0e39'
    t 'respawn()' '~^Interactive Elixir [^|]*$'
    t 'hex(255)' '0xFF'
    t 'gb(512, mb)' '0.5'
    t 'hex(byte(2, mb))' '0x200000'
    t 'kb(-2049, s64)' '-2'
    iex_session iex "$WORK/iex.exs"
    documented iex
    iex_session 'iex, as documented' "$WORK/iex.exs"

    sed '/^if Code.ensure_loaded/,$d' "$WORK/iex.exs" >"$WORK/plain.exs"
    t 'bin(hex(5) + 1)' "$EACH"
    iex_session 'iex without its hooks' "$WORK/plain.exs"
else
    echo "SKIP  repl: iex is not installed"
fi

if command -v node >/dev/null 2>&1; then
    t 'hex(255)' '0xFF'
    t 'hex(hex(bin(0x1000) * 64) << 4) - 0x100' '0x3FFF00'
    t 'bin(hex(0x10) << 2)' '0b1000000'
    t 'hex(1) + bin(2)' '0b11'
    t 'hex(~0x1000)' '0xFFFFFFFFFFFFEFFF'
    t 'dec(~0x1000, s64)' '-4097n'
    t 'dec(~0x1000, s32)' '-4097'
    t 'hex(-1, u16)' '0xFFFF'
    t 'hex(0x12345, "U16")' '0x2345'
    t 'bin(0x1000, hex)' '0x1000'
    t 'u8(300) + s8(200)' '-12'
    t 'hex(-1n) >> 4n' '0xFFFFFFFFFFFFFFFn'
    t 'hex(-1, "int")' '0xFFFFFFFF'
    t 'dec(200, "signed char")' '-56'
    t 'cast("unsigned long", -1)' '18446744073709551615n'
    t 'sizeof("int")' '4'
    t 'hex(1.5)' '0x1.8'
    t 'hex(0.1, f32)' '0x0.199999A'
    t 'hex("A")' '0x41'
    t 'hex(255n)' '0xFFn'
    t 'u64(-1)' '18446744073709551615n'
    t 'hex(1n << 64n)' "$WIDE; pass big to keep all of it | 0x0n"
    t 'hex(1n << 64n, big)' '0x10000000000000000n'
    t 'hex(0xffffffff81001234)' '~^hex: 18446744071578850000 is past 2\*\*53, .* \| 0xFFFFFFFF81001000$'
    t 'x = hex(0x12345, u16)' '0x2345'
    t 'x' '9029'
    t 'typeof hex(5)' "'number'"
    t '[hex(1), bin(2)]' '[ 1, 2 ]'
    t 'hex("AB")' "~TypeError: hex\(\) expects a single character, got 'AB' \(2 code points\)"
    t '7' '7'
    t 'hex(1, "foo")' "~hex\(\) expects options among $NAMES, big or a C type name, got 'foo'"
    t 'hex(1, "__proto__")' "~or a C type name, got '__proto__'"
    t 'hex(1, u8, u16)' '~hex\(\) takes one type, got u8 and u16'
    t 'hex(NaN)' '~RangeError: hex\(\) expects a finite number, got NaN'
    t 'u8(1, 2)' '~u8\(\) takes one value, got 2'
    t 'gb(512, mb)' '0.5'
    t 'hex(byte(2, mb))' '0x200000'
    t 'kb(-2049, s64)' '-2n'
    node_session node "--require $WORK/repl.js"
    documented node
    node_session 'node, as documented' "--require $WORK/repl.js"

    echo 'Object.defineProperty(require("node:repl"), "start", { writable: false });' >"$WORK/fixed.js"
    t 'bin(hex(5) + 1)' "$EACH"
    node_session 'node without its hooks' "--require $WORK/fixed.js --require $WORK/repl.js"

    is 'node -p defines nothing' "$(clean NODE_OPTIONS="--require $WORK/repl.js" node -p 'typeof hex')" undefined
    is 'a node script defines nothing' "$(echo 'console.log(typeof hex)' | clean NODE_OPTIONS="--require $WORK/repl.js" node -)" undefined
else
    echo "SKIP  repl: node is not installed"
fi

if command -v luajit >/dev/null 2>&1; then
    init="if jit then pcall(dofile, '$WORK/repl.lua') end"
    t '=hex(255)' '0xFF'
    t '=hex(lshift(hex(bin(0x1000) * 64), 4)) - 0x100' '0x3FFF00'
    t '=bin(lshift(hex(0x10), 2))' '0b1000000'
    t '=hex(1) + bin(2)' '0b11'
    t '=hex(bnot(0x1000))' '0xFFFFFFFFFFFFEFFF'
    t '=dec(bnot(0x1000), s64)' '-4097'
    t '=hex(-1, u16)' '0xFFFF'
    t '=hex(0x12345, "U16")' '0x2345'
    t '=bin(0x1000, hex)' '0x1000'
    t '=u8(300) + s8(200)' '-12'
    t '=u32(0xFFFFFFFF) + 1' '0'
    t '=s32(-7) / 2' '-3'
    t '=s32(-7) % 2' '-1'
    t '=u8(250) + u8(10)' '260'
    t '=(u8(250) + u8(10)).type' 's32'
    t '=s32(-1) < u32(1)' 'false'
    t '=hex(rshift(u64(-1), 60))' '0xF'
    t '=hex(arshift(s64(-1), 60))' '0xFFFFFFFFFFFFFFFF'
    t '=hex(-1, "int")' '0xFFFFFFFF'
    t '=dec(200, "signed char")' '-56'
    t '=cast("unsigned long", -1)' '18446744073709551615'
    t '=sizeof("int") - 5' '18446744073709551615'
    t '=u32(7) / 0' '~^attempt to divide by zero'
    t '=hex(1.5)' '0x1.8'
    t '=hex(0.1, f32)' '0x0.199999A'
    t '=hex("A")' '0x41'
    t '=hex(255ULL)' '0xFF'
    t '=u64(-1)' '18446744073709551615'
    t '=hex(0xffffffffffffffffULL + 1)' '0x0'
    t '=hex(2^64)' "~^hex: 18446744073709551616 is past 2\^53, .* \| $WIDE \| 0x0$"
    t 'x = hex(16)' ''
    t '=x' '16'
    t 'print(hex(255), 10)' $'0xFF\t0xA'
    t '=hex("AB")' '~^hex expects a single character, got "AB" \(2 code points\)'
    t '=7' '7'
    t '=hex(1, "foo")' "~hex expects options among $NAMES or a C type name, got \"foo\""
    t '=hex(1, u8, u16)' '~hex takes one type, got u8 and u16'
    t '=hex(0/0)' '~hex expects a finite number, got -?nan'
    t '=u8(1, 2)' '~u8 takes one value, got 2'
    t '=gb(512, mb)' '0.5'
    t '=hex(byte(2, mb))' '0x200000'
    t '=kb(-2049, s64)' '-2'
    luajit_session luajit "$init"
    documented luajit
    luajit_session 'luajit, as documented' "$init"

    t '=bin(hex(5) + 1)' "$EACH"
    luajit_session 'luajit without its hooks' "setmetatable(_G, { __metatable = false }) $init"

    is 'luajit -e defines nothing' "$(clean LUA_INIT="$init" luajit -e 'print(hex)')" nil
    is 'a luajit script defines nothing' "$(echo 'print(hex)' | clean LUA_INIT="$init" luajit -)" nil
    if command -v lua >/dev/null 2>&1; then
        is 'lua runs the same LUA_INIT' "$(clean LUA_INIT="$init" lua -e 'print(hex)')" nil
    fi
else
    echo "SKIP  repl: luajit is not installed"
fi

if command -v racket >/dev/null 2>&1; then
    t 'hex(255)' '0xFF'
    t '-7 / 2' '-3'
    t '(unsigned char)300' '44'
    t 'hex(~0xFFF)' '0xFFFFFFFFFFFFF000'
    t 'gb(512, mb)' '0.5'
    t 'twice(a) = a * 2; twice(21)' '42'
    cnum_session cnum
    documented cnum
    cnum_session 'cnum, as documented'
    is 'cnum evaluates its arguments' "$(clean racket "$WORK/cnum.rkt" 'x = 6' 'hex(x * 7)' | tr '\n' ' ')" '6 0x2A '
    is 'cnum fails on a bad argument' "$(
        clean racket "$WORK/cnum.rkt" '1 +' >/dev/null
        echo $?
    )" 1
    mkdir -p "$WORK/home/.config/cnum"
    printf 'PAGE_SIZE = 0x1000\nup(v) = (v + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)\n' >"$WORK/home/.config/cnum/init"
    is 'cnum runs its init file' "$(clean racket "$WORK/cnum.rkt" 'hex(up(0x1234))')" 0x2000
    rm -r "$WORK/home/.config/cnum"
else
    echo "SKIP  repl: racket is not installed"
fi

printf '#!/bin/sh\n' >"$WORK/bin/luajit"
chmod +x "$WORK/bin/luajit"
ours="if jit then pcall(dofile, '$WORK/with/.config/luajit/repl.lua') end"
lua_init() { env -i PATH="$1" HOME="$2" ${3:+LUA_INIT="$3"} /bin/sh -c '. "$1"; echo "${LUA_INIT-unset}"' sh "$REPO/luajit/luajit.sh"; }
is 'luajit.sh sets LUA_INIT' "$(lua_init "$WORK/bin" "$WORK/with" '')" "$ours"
is 'luajit.sh without the file' "$(lua_init "$WORK/bin" "$WORK/plain" '')" unset
is 'luajit.sh without luajit' "$(lua_init /nonexistent "$WORK/with" '')" unset
is 'luajit.sh keeps another LUA_INIT' "$(lua_init "$WORK/bin" "$WORK/with" '@/other')" '@/other'
is 'luajit.sh drops its own stale LUA_INIT' "$(lua_init /nonexistent "$WORK/with" "$ours")" unset

if ((failed)); then
    echo "FAIL  repl: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  repl: $passed checks"
