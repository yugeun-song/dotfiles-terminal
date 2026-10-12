"use strict";

const { inspect } = require("node:util");

const BASES = {
  hex: { radix: 16, prefix: "0x", upper: true },
  bin: { radix: 2, prefix: "0b", upper: false },
  oct: { radix: 8, prefix: "0o", upper: false },
};

function unwrap(input) {
  if (
    input instanceof NumValue ||
    input instanceof BigValue ||
    input instanceof Number ||
    input instanceof Boolean ||
    input instanceof String ||
    input instanceof BigInt
  ) {
    return input.valueOf();
  }
  return input;
}

function toValue(name, input) {
  const value = unwrap(input);

  switch (typeof value) {
    case "number":
      if (!Number.isFinite(value)) {
        throw new RangeError(`${name}() expects a finite number, got ${value}`);
      }
      return value;
    case "bigint":
      return value;
    case "boolean":
      return value ? 1 : 0;
    case "string": {
      const chars = [...value];
      if (chars.length !== 1) {
        throw new TypeError(
          `${name}() expects a single character, got ${JSON.stringify(value)} (${chars.length} code points)`,
        );
      }
      return chars[0].codePointAt(0);
    }
    default:
      throw new TypeError(
        `${name}() expects a number, bigint, boolean, or single character, got ${value === null ? "null" : typeof value}`,
      );
  }
}

function format(base, value) {
  const negative = value < 0 || Object.is(value, -0);
  const magnitude = negative ? -value : value;
  let digits = magnitude.toString(base.radix);

  if (base.upper) {
    digits = digits.toUpperCase();
  }

  const suffix = typeof value === "bigint" ? "n" : "";
  return `${negative ? "-" : ""}${base.prefix}${digits}${suffix}`;
}

class NumValue extends Number {
  #base;

  constructor(base, value) {
    super(value);
    this.#base = base;
  }

  [inspect.custom]() {
    return format(this.#base, this.valueOf());
  }
}

class BigValue {
  #base;
  #value;

  constructor(base, value) {
    this.#base = base;
    this.#value = value;
  }

  valueOf() {
    return this.#value;
  }

  toString(radix) {
    return this.#value.toString(radix);
  }

  [Symbol.toPrimitive]() {
    return this.#value;
  }

  [inspect.custom]() {
    return format(this.#base, this.#value);
  }
}

function makeHelper(name) {
  const base = BASES[name];
  const helper = (input) => {
    const value = toValue(name, input);
    return typeof value === "bigint"
      ? new BigValue(base, value)
      : new NumValue(base, value);
  };
  Object.defineProperty(helper, "name", { value: name });
  return helper;
}

const hex = makeHelper("hex");
const bin = makeHelper("bin");
const oct = makeHelper("oct");

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
  for (const [name, fn] of Object.entries({ hex, bin, oct })) {
    if (!(name in globalThis)) {
      Object.defineProperty(globalThis, name, {
        value: fn,
        writable: true,
        configurable: true,
        enumerable: false,
      });
    }
  }
}
