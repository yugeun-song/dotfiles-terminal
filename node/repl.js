"use strict";

const { inspect } = require("node:util");

const BASES = { bin: [2, "0b"], oct: [8, "0o"], dec: [10, ""], hex: [16, "0x"] };
const INTS = Object.fromEntries(
  [8, 16, 32, 64].flatMap((bits) => [
    [`u${bits}`, [bits, false]],
    [`s${bits}`, [bits, true]],
  ]),
);
const FLOATS = { f32: Math.fround, f64: Number };
const NAMES = [...Object.keys(BASES), ...Object.keys(INTS), ...Object.keys(FLOATS), "big"];
const BOXES = [Number, Boolean, String, BigInt];

const helpers = new Map();
const state = { shown: null, hooked: false, noted: false };

function note(message) {
  process.stderr.write(`${message}\n`);
}

function describe(value) {
  let text;
  try {
    text = inspect(value, { depth: 0, breakLength: Infinity, maxStringLength: 64, maxArrayLength: 8 });
  } catch {
    text = "a value that cannot be shown";
  }
  return text.length > 80 ? `${text.slice(0, 77)}...` : text;
}

function inexact(name, value) {
  if (typeof value !== "number" || !Number.isInteger(value) || Number.isSafeInteger(value)) return;
  if (state.hooked && state.noted) return;
  state.noted = true;
  note(`${name}: ${value} is past 2**53, where a number is no longer exact; write it as a BigInt (0x...n)`);
}

function codePoint(name, text) {
  if (/\p{Surrogate}/u.test(text)) {
    throw new TypeError(`${name}() expects a well-formed character, got ${describe(text)}`);
  }
  let count = 0;
  for (const _ of text) count += 1;
  if (count !== 1) {
    throw new TypeError(`${name}() expects a single character, got ${describe(text)} (${count} code points)`);
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
      if (!Number.isFinite(value)) throw new RangeError(`${name}() expects a finite number, got ${value}`);
      inexact(name, value);
      return value;
    case "string":
      return codePoint(name, value);
    default:
      throw new TypeError(
        `${name}() expects a number, bigint, boolean, or single character, got ${describe(value)}`,
      );
  }
}

function one(name, kind, old, key) {
  if (old !== undefined && old !== key) throw new TypeError(`${name}() takes one ${kind}, got ${old} and ${key}`);
  return key;
}

function pick(name, options) {
  let base;
  let type;
  for (const option of options) {
    const key = helpers.get(option) || (typeof option === "string" ? option.toLowerCase() : undefined);
    if (!NAMES.includes(key)) {
      throw new TypeError(`${name}() expects options among ${NAMES.join(", ")}, got ${describe(option)}`);
    }
    if (key in BASES) base = one(name, "base", base, key);
    else type = one(name, "type", type, key);
  }
  return [base || name, type];
}

function cast(type, value) {
  if (type in FLOATS) return FLOATS[type](Number(value));
  const whole = typeof value === "bigint" ? value : BigInt(Math.trunc(value));
  if (type === "big") return whole;
  const [bits, signed] = INTS[type];
  const wrapped = (signed ? BigInt.asIntN : BigInt.asUintN)(bits, whole);
  return bits < 64 && typeof value === "number" ? Number(wrapped) : wrapped;
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

function render(name, value, base, type) {
  const [radix, prefix] = BASES[base];
  const suffix = typeof value === "bigint" ? "n" : "";
  if (type in FLOATS) return real(cast(type, value), radix, prefix);
  if (!type && typeof value === "number" && !Number.isInteger(value)) return real(value, radix, prefix);

  const integer = cast("big", value);
  if (type === "big") return whole(integer, radix, prefix) + suffix;
  if (!type && integer !== BigInt.asIntN(64, integer) && integer !== BigInt.asUintN(64, integer)) {
    note(`${name}: the value is wider than 64 bits and only the low 64 are shown; pass big to see all of it`);
  }
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
  inexact(name, value);
  return render(name, value, base, type);
}

function define(name, body) {
  Object.defineProperty(body, "name", { value: name });
  helpers.set(body, name);
  return body;
}

for (const name of Object.keys(BASES)) {
  define(name, (input, ...options) => {
    const value = number(name, input);
    const [base, type] = pick(name, options);
    state.shown = [name, base, type];
    if (!state.hooked) console.log(render(name, value, base, type));
    return value;
  });
}

for (const name of NAMES.slice(Object.keys(BASES).length)) {
  define(name, (input, ...rest) => {
    if (rest.length > 0) throw new TypeError(`${name}() takes one value, got ${rest.length + 1}`);
    return cast(name, number(name, input));
  });
}

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
    return writer.call(this, { [inspect.custom]: (depth, options) => options.stylize(text, typeof value) });
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
  for (const [body, name] of helpers) {
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
