"use strict";

const { inspect } = require("node:util");

const BASES = { bin: [2, "0b"], oct: [8, "0o"], dec: [10, ""], hex: [16, "0x"] };
const INTS = Object.fromEntries(
  [8, 16, 32, 64].flatMap((bits) => [
    [`u${bits}`, [bits, false]],
    [`s${bits}`, [bits, true]],
  ]),
);
const FLOATS = { f32: 4, f64: 8 };
const NAMES = [...Object.keys(BASES), ...Object.keys(INTS), ...Object.keys(FLOATS), "big"];
const KNOWN = new Map([
  ...NAMES.map((name) => [name, name]),
  ...Object.entries(INTS).map(([name, [bits, signed]]) => [
    `${signed ? "" : "u"}int${bits}_t`,
    name,
  ]),
  ["size_t", "u64"],
  ["ssize_t", "s64"],
  ["intptr_t", "s64"],
  ["uintptr_t", "u64"],
  ["ptrdiff_t", "s64"],
  ["intmax_t", "s64"],
  ["uintmax_t", "u64"],
  ["uint", "u32"],
  ["ulong", "u64"],
  ["ushort", "u16"],
  ["float", "f32"],
  ["double", "f64"],
]);
const WORDS = new Map([
  ["signed", 1],
  ["unsigned", 1],
  ["char", 1],
  ["short", 1],
  ["int", 1],
  ["long", 2],
]);
const APART = [
  ["signed", "unsigned"],
  ["char", "short", "long"],
  ["char", "int"],
];
const SIZES = [
  ["char", 8],
  ["short", 16],
  ["long", 64],
];
const BOXES = [Number, Boolean, String, BigInt];
const UNITS = ["byte", "kb", "mb", "gb", "tb"];
const SPELLED = new Map([
  ["b", "byte"],
  ["byte", "byte"],
  ["bytes", "byte"],
  ...[
    ["kb", "kilo", "kibi"],
    ["mb", "mega", "mebi"],
    ["gb", "giga", "gibi"],
    ["tb", "tera", "tebi"],
  ].flatMap(([unit, ...words]) => [
    [unit, unit],
    [`${unit[0]}ib`, unit],
    ...words.flatMap((word) => [
      [`${word}byte`, unit],
      [`${word}bytes`, unit],
    ]),
  ]),
]);

const helpers = new Map();
const units = new Map();
const extras = new Map();
const state = { shown: null, hooked: false, noted: false };

function note(message) {
  process.stderr.write(`${message}\n`);
}

function describe(value) {
  let text;
  try {
    text = inspect(value, {
      depth: 0,
      breakLength: Infinity,
      maxStringLength: 64,
      maxArrayLength: 8,
    });
  } catch {
    text = "a value that cannot be shown";
  }
  return text.length > 80 ? `${text.slice(0, 77)}...` : text;
}

function inexact(name, value) {
  if (typeof value !== "number" || !Number.isInteger(value) || Number.isSafeInteger(value)) return;
  if (state.hooked && state.noted) return;
  state.noted = true;
  note(
    `${name}: ${value} is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`,
  );
}

function codePoint(name, text) {
  if (/\p{Surrogate}/u.test(text)) {
    throw new TypeError(`${name}() expects a well-formed character, got ${describe(text)}`);
  }
  let count = 0;
  for (const _ of text) count += 1;
  if (count !== 1) {
    throw new TypeError(
      `${name}() expects a single character, got ${describe(text)} (${count} code points)`,
    );
  }
  return text.codePointAt(0);
}

function number(name, input) {
  const value = BOXES.some((box) => input instanceof box) ? input.valueOf() : input;

  switch (typeof value) {
    case "bigint":
      return value;
    case "boolean":
      return Number(value);
    case "number":
      if (!Number.isFinite(value))
        throw new RangeError(`${name}() expects a finite number, got ${value}`);
      return value;
    case "string":
      return codePoint(name, value);
    default:
      throw new TypeError(
        `${name}() expects a number, bigint, boolean, or single character, got ${describe(value)}`,
      );
  }
}

function specifiers(words) {
  const counts = new Map();
  for (const word of words) counts.set(word, (counts.get(word) || 0) + 1);
  const declared =
    counts.size > 0 &&
    [...counts].every(([word, count]) => count <= (WORDS.get(word) || 0)) &&
    !APART.some((group) => group.filter((word) => counts.has(word)).length > 1);
  if (!declared) return undefined;
  const size = SIZES.find(([word]) => counts.has(word));
  return `${counts.has("unsigned") ? "u" : "s"}${size ? size[1] : 32}`;
}

function resolve(option) {
  if (helpers.has(option)) return helpers.get(option);
  if (typeof option !== "string") return undefined;
  const words = option.toLowerCase().split(/\s+/).filter(Boolean);
  return KNOWN.get(words.join(" ")) || specifiers(words);
}

function one(name, kind, old, key) {
  if (old !== undefined && old !== key)
    throw new TypeError(`${name}() takes one ${kind}, got ${old} and ${key}`);
  return key;
}

function pick(name, options) {
  let base;
  let type;
  for (const option of options) {
    const key = resolve(option);
    if (key === undefined) {
      throw new TypeError(
        `${name}() expects options among ${NAMES.join(", ")} or a C type name, got ${describe(option)}`,
      );
    }
    if (key in BASES) base = one(name, "base", base, key);
    else type = one(name, "type", type, key);
  }
  return [base || name, type];
}

function kind(name, option) {
  const key = resolve(option);
  if (key === undefined || key in BASES) {
    const types = NAMES.slice(Object.keys(BASES).length).join(", ");
    throw new TypeError(
      `${name}() expects a type among ${types} or a C type name, got ${describe(option)}`,
    );
  }
  return key;
}

function nearest(value, bits) {
  const size = value < 0n ? -value : value;
  const shift = BigInt(Math.max(size.toString(2).length - bits, 0));
  let quotient = size >> shift;
  if (((size - (quotient << shift)) << 1n) + (quotient & 1n) > 1n << shift) quotient += 1n;
  return Number(quotient << shift) * (value < 0n ? -1 : 1);
}

function to(name, type, value) {
  if (type === "f32") return Math.fround(typeof value === "bigint" ? nearest(value, 24) : value);
  if (type === "f64") return Number(value);
  inexact(name, value);
  const whole = typeof value === "bigint" ? value : BigInt(Math.trunc(value));
  if (type === "big") return whole;
  const [bits, signed] = INTS[type];
  const wrapped = (signed ? BigInt.asIntN : BigInt.asUintN)(bits, whole);
  return bits < 64 && typeof value === "number" ? Number(wrapped) : wrapped;
}

function wide(name, integer) {
  if (integer === BigInt.asIntN(64, integer) || integer === BigInt.asUintN(64, integer)) return;
  note(
    `${name}: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it`,
  );
}

function convert(name, value, type) {
  if (type) return to(name, type, value);
  inexact(name, value);
  if (typeof value !== "bigint") return value;
  wide(name, value);
  return BigInt.asUintN(64, value);
}

function whole(value, radix, prefix) {
  const sign = value < 0n ? "-" : "";
  return `${sign}${prefix}${(value < 0n ? -value : value).toString(radix).toUpperCase()}`;
}

function real(value, radix, prefix) {
  if (radix === 10 || !Number.isFinite(value)) return Object.is(value, -0) ? "-0" : String(value);
  const size = Math.abs(value);
  let rest = size - Math.trunc(size);
  let digits = rest > 0 ? "." : "";
  while (rest > 0) {
    rest *= radix;
    digits += Math.trunc(rest).toString(radix).toUpperCase();
    rest -= Math.trunc(rest);
  }
  const sign = value < 0 || Object.is(value, -0) ? "-" : "";
  return `${sign}${whole(BigInt(Math.trunc(size)), radix, prefix)}${digits}`;
}

function places(value) {
  const [digits, rest] = Math.abs(value).toFixed(100).split(".");
  const kept = (rest.startsWith("00000") ? rest.slice(0, 20) : rest.slice(0, 5)).replace(/0+$/, "");
  if (kept === "") return digits === "0" ? String(value) : `${value < 0 ? "-" : ""}${digits}`;
  return `${value < 0 ? "-" : ""}${digits}.${kept}`;
}

function sized(name, value, type) {
  if (typeof value !== "number" || (type && !(type in FLOATS)))
    return render(name, value, "dec", type);
  if (Number.isInteger(value))
    return Math.abs(value) < 1e21 ? BigInt(value).toString() : String(value);
  return places(value);
}

function unit(option) {
  if (units.has(option)) return units.get(option);
  return typeof option === "string" ? SPELLED.get(option.trim().toLowerCase()) : undefined;
}

function measures(name, options) {
  let from;
  let type;
  for (const option of options) {
    const key = unit(option);
    const other = key === undefined ? resolve(option) : undefined;
    if (key !== undefined) from = one(name, "unit", from, key);
    else if (other !== undefined && !(other in BASES)) type = one(name, "type", type, other);
    else {
      const names = [...UNITS, ...NAMES.slice(Object.keys(BASES).length)].join(", ");
      throw new TypeError(
        `${name}() expects options among ${names} or a C type name, got ${describe(option)}`,
      );
    }
  }
  return [from || "byte", type];
}

function scale(name, value, shift, type) {
  const size = Math.abs(shift);
  if (type in FLOATS || (!type && typeof value === "number")) {
    const scaled = (type ? to(name, type, value) : value) * 2 ** shift;
    return [type === "f32" ? Math.fround(scaled) : scaled, type];
  }
  const factor = 1n << BigInt(size);
  if (!type || type === "big") {
    const whole = type ? to(name, type, value) : convert(name, value, type);
    if (shift >= 0) return [type ? whole * factor : BigInt.asUintN(64, whole * factor), type];
    if (whole % factor === 0n) return [whole / factor, type];
    return [Number(whole) / 2 ** size, undefined];
  }
  const [bits, signed] = INTS[type];
  const width = Math.max(bits, size > 30 ? 64 : 32);
  const cut = signed || width > bits ? BigInt.asIntN : BigInt.asUintN;
  const whole = cut(width, BigInt(to(name, type, value)));
  const scaled = cut(width, shift < 0 ? whole / factor : whole * factor);
  return [
    width < 64 && typeof value === "number" ? Number(scaled) : scaled,
    `${cut === BigInt.asIntN ? "s" : "u"}${width}`,
  ];
}

function measure(name, target, input, options) {
  const given = number(name, input);
  const [from, type] = measures(name, options);
  const [value, shown] = scale(
    name,
    given,
    10 * (UNITS.indexOf(from) - UNITS.indexOf(target)),
    type,
  );
  state.shown = [name, "size", shown];
  if (!state.hooked) console.log(render(name, value, "size", shown));
  return value;
}

function render(name, value, base, type) {
  if (base === "size") return sized(name, value, type);
  const [radix, prefix] = BASES[base];
  const suffix = typeof value === "bigint" ? "n" : "";
  if (type in FLOATS) return real(to(name, type, value), radix, prefix);
  if (!type && typeof value === "number" && !Number.isInteger(value))
    return real(value, radix, prefix);

  const integer = to(name, "big", value);
  if (type === "big") return whole(integer, radix, prefix) + suffix;
  if (!type) wide(name, integer);
  const [bits, signed] = INTS[type || "u64"];
  const digits =
    radix === 10
      ? (signed ? BigInt.asIntN : BigInt.asUintN)(bits, integer).toString()
      : whole(BigInt.asUintN(bits, integer), radix, prefix);
  return digits + suffix;
}

function result(value) {
  if (!state.shown || !(typeof value === "bigint" || Number.isFinite(value))) return undefined;
  const [name, base, type] = state.shown;
  return render(name, value, base, type);
}

function sizeof(operand) {
  if (typeof operand === "number" || typeof operand === "bigint") {
    if (typeof operand === "number" && !Number.isInteger(operand)) return 8;
    return (operand < 0 ? -operand : operand) < 2147483648 ? 4 : 8;
  }
  const type = kind("sizeof", operand);
  if (type === "big") throw new TypeError("sizeof() expects a type with a size, got big");
  return type in FLOATS ? FLOATS[type] : INTS[type][0] / 8;
}

function define(table, name, body) {
  Object.defineProperty(body, "name", { value: name });
  table.set(body, name);
  return body;
}

for (const name of Object.keys(BASES)) {
  define(helpers, name, (input, ...options) => {
    const given = number(name, input);
    const [base, type] = pick(name, options);
    const value = convert(name, given, type);
    state.shown = [name, base, type];
    if (!state.hooked) console.log(render(name, value, base, type));
    return value;
  });
}

for (const name of NAMES.slice(Object.keys(BASES).length)) {
  define(helpers, name, (input, ...rest) => {
    if (rest.length > 0) throw new TypeError(`${name}() takes one value, got ${rest.length + 1}`);
    return to(name, name, number(name, input));
  });
}

for (const name of UNITS) {
  define(units, name, (input, ...options) => measure(name, name, input, options));
  for (const target of UNITS) {
    if (target !== name) {
      const both = `${name}_to_${target}`;
      define(extras, both, (input, ...options) => measure(both, target, input, [name, ...options]));
    }
  }
}

define(extras, "cast", (type, input) => to("cast", kind("cast", type), number("cast", input)));
define(extras, "sizeof", sizeof);

function hook(server) {
  const { eval: evaluate, writer } = server;

  server.eval = function (...args) {
    state.shown = null;
    state.noted = false;
    return evaluate.apply(this, args);
  };

  server.writer = Object.assign(function (value) {
    let text;
    try {
      text = result(value);
    } catch {
      text = undefined;
    }
    if (text === undefined) return writer.call(this, value);
    return writer.call(this, {
      [inspect.custom]: (depth, options) => options.stylize(text, typeof value),
    });
  }, writer);

  state.hooked = true;
}

function install() {
  const repl = require("node:repl");
  const { start } = repl;

  repl.start = function (...args) {
    const server = start.apply(this, args);
    hook(server);
    return server;
  };
}

const nonRepl = /^(-e|-p|-pe|--eval|--print|-c|--check|--test|--run|--watch)(=|$)/;
const interactive = process.execArgv.some((a) => a === "-i" || a === "--interactive");

function isInteractiveRepl() {
  try {
    return (
      require("node:worker_threads").isMainThread &&
      process.argv.length === 1 &&
      !process.execArgv.some((a) => nonRepl.test(a)) &&
      (interactive || require("node:tty").isatty(0))
    );
  } catch {
    return false;
  }
}

if (isInteractiveRepl()) {
  for (const [body, name] of [...helpers, ...units, ...extras]) {
    if (!(name in globalThis)) {
      Object.defineProperty(globalThis, name, {
        value: body,
        writable: true,
        configurable: true,
        enumerable: false,
      });
    }
  }

  try {
    install();
  } catch {
    state.hooked = false;
  }
}
