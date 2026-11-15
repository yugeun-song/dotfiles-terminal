unless Code.ensure_loaded?(IExHelpers) do
  defmodule IExHelpers do
    @moduledoc """
    Number-base and size helpers for IEx that convert as C does on x86-64 Linux (GCC, LP64).

    Elixir's operators cannot be changed, so a conversion cuts where it is called and returns a
    plain number. The result line shows the statement's value once, in the base called last.
    """
    import Bitwise

    @bases [bin: {2, "0b"}, oct: {8, "0o"}, dec: {10, ""}, hex: {16, "0x"}]
    @ints for bits <- [8, 16, 32, 64],
              {sign, signed} <- [u: false, s: true],
              do: {:"#{sign}#{bits}", {bits, signed}}
    @floats [f32: 4, f64: 8]
    @types Keyword.keys(@ints) ++ Keyword.keys(@floats) ++ [:big]
    @names Keyword.keys(@bases) ++ @types
    @known Map.new(@names, &{Atom.to_string(&1), &1})
           |> Map.merge(
             Map.new(@ints, fn {name, {bits, signed}} ->
               {"#{if signed, do: "", else: "u"}int#{bits}_t", name}
             end)
           )
           |> Map.merge(%{
             "size_t" => :u64,
             "ssize_t" => :s64,
             "intptr_t" => :s64,
             "uintptr_t" => :u64,
             "ptrdiff_t" => :s64,
             "intmax_t" => :s64,
             "uintmax_t" => :u64,
             "uint" => :u32,
             "ulong" => :u64,
             "ushort" => :u16,
             "float" => :f32,
             "double" => :f64
           })
    @words %{"signed" => 1, "unsigned" => 1, "char" => 1, "short" => 1, "int" => 1, "long" => 2}
    @apart [~w(signed unsigned), ~w(char short long), ~w(char int)]
    @sizes %{"char" => 8, "short" => 16, "long" => 64}
    @units [:byte, :kb, :mb, :gb, :tb]
    @spelled for {unit, words} <- [
                   kb: ~w(kilo kibi),
                   mb: ~w(mega mebi),
                   gb: ~w(giga gibi),
                   tb: ~w(tera tebi)
                 ],
                 text <-
                   [Atom.to_string(unit), String.first(Atom.to_string(unit)) <> "ib"] ++
                     Enum.flat_map(words, &[&1 <> "byte", &1 <> "bytes"]),
                 into: %{"b" => :byte, "byte" => :byte, "bytes" => :byte},
                 do: {text, unit}
    @shown {__MODULE__, :shown}

    for name <- @names do
      @doc "Its own name, so that `hex(x, #{name})` can name it as an option."
      def unquote(name)(), do: unquote(name)
    end

    for {name, {radix, prefix}} <- @bases do
      @doc """
      Shows `value` in base #{radix}#{if prefix != "", do: ", with a `#{prefix}` prefix"} and returns it converted.

      An option is a type (`u8` to `s64`, `f32`, `f64`, `big`, or a C name such as `:int` or
      `"unsigned long"`), which converts as a C cast does, or a base, which shows that base
      instead. With no type an integer is cut to a `u64`, and a float keeps its fraction.
      `true` and `false` are 1 and 0, and a one-character string is its code point.
      """
      def unquote(name)(value), do: show(unquote(name), value, [])
      def unquote(name)(value, option), do: show(unquote(name), value, [option])
      def unquote(name)(value, option, other), do: show(unquote(name), value, [option, other])
    end

    for name <- @types do
      @doc """
      Converts `value` as C's `(#{name})value` does#{if name == :big, do: ", with no width: nothing is cut"}.

      A float loses its fraction for an integer type, and what does not fit the width is cut;
      a negative number becomes its two's complement pattern for an unsigned type.
      """
      def unquote(name)(value), do: to(unquote(name), number(unquote(name), value))
    end

    for unit <- @units do
      @doc "Its own name, so that `gb(x, #{unit})` can name it as the unit `x` is in."
      def unquote(unit)(), do: unquote(unit)

      @doc """
      Converts a size to `#{unit}`, in steps of 1024. `value` is in bytes unless a unit is among
      the options: `#{unit}(x, gb)`, `:megabyte`, `"MiB"`.

      A whole result is an integer, cut to a `u64`. When the division leaves a remainder the
      result is a float, shown to 5 places, or to 20 when the first 5 are zeros. A type among
      the options converts `value` first and computes as C would: the division truncates.
      """
      def unquote(unit)(value), do: size(unquote(unit), unquote(unit), value, [])

      def unquote(unit)(value, option),
        do: size(unquote(unit), unquote(unit), value, [option])

      def unquote(unit)(value, option, other),
        do: size(unquote(unit), unquote(unit), value, [option, other])
    end

    for from <- @units, to <- @units, from != to do
      name = :"#{from}_to_#{to}"

      @doc "Converts `value` from `#{from}` to `#{to}`: `#{to}(value, #{from})`. An option names a type."
      def unquote(name)(value), do: size(unquote(name), unquote(to), value, [unquote(from)])

      def unquote(name)(value, option),
        do: size(unquote(name), unquote(to), value, [unquote(from), option])
    end

    @doc """
    Converts `value` to `type` as C's `(type)value` does. `type` is any name a helper takes:
    `u16`, `:u16`, `:int`, `:uint32_t`, `"unsigned long"`, `:double`, `big`.
    """
    def cast(type, value), do: to(type("cast", type), number("cast", value))

    @doc """
    The size in bytes of a type, as C's `sizeof`. A number counts as the constant it would be
    in C: 4 for an integer that fits an `int`, else 8, and 8 for a float.
    """
    def sizeof(value) when is_float(value), do: 8
    def sizeof(value) when is_integer(value), do: if(abs(value) < 1 <<< 31, do: 4, else: 8)

    def sizeof(type) do
      case type("sizeof", type) do
        :big -> raise ArgumentError, "sizeof expects a type with a size, got big"
        name -> @floats[name] || div(elem(@ints[name], 0), 8)
      end
    end

    @doc false
    def __reset__, do: Process.put(@shown, :none)

    @doc false
    def __parse__(input, opts, state) do
      with {:ok, forms, state} <- IEx.Evaluator.parse(input, opts, state) do
        {:ok, reset(forms), state}
      end
    end

    @doc false
    def __inspect__(term, opts) do
      shown = Process.get(@shown)
      if is_tuple(shown), do: Process.put(@shown, :none)

      with {name, base, type} when is_number(term) <- shown,
           {:ok, text} <- rendered(name, term, base, type) do
        Inspect.Algebra.color(text, :number, opts)
      else
        _ -> Inspect.inspect(term, opts)
      end
    end

    defp rendered(name, term, base, type) do
      {:ok, render(convert(name, term, type), base, type)}
    rescue
      _ -> :error
    end

    defp reset(forms) when is_function(forms, 0), do: fn -> reset(forms.()) end
    defp reset({:__block__, _, []} = empty), do: empty

    defp reset({:__block__, meta, forms}),
      do: {:__block__, meta, [quote(do: unquote(__MODULE__).__reset__()) | forms]}

    defp reset(form), do: {:__block__, [], [quote(do: unquote(__MODULE__).__reset__()), form]}

    defp show(name, value, options) do
      number = number(name, value)
      {base, type} = pick(name, options)
      number = convert(name, number, type)

      case Process.get(@shown) do
        nil -> IO.puts(render(number, base, type))
        _ -> Process.put(@shown, {name, base, type})
      end

      number
    end

    defp size(name, unit, value, options) do
      number = number(name, value)
      {from, type} = units(name, options)

      shift =
        10 * (Enum.find_index(@units, &(&1 == from)) - Enum.find_index(@units, &(&1 == unit)))

      {number, type} = scale(name, number, shift, type)

      case Process.get(@shown) do
        nil -> IO.puts(render(number, :size, type))
        _ -> Process.put(@shown, {name, :size, type})
      end

      number
    end

    defp units(name, options) do
      {unit, type} =
        Enum.reduce(options, {nil, nil}, fn option, {unit, type} ->
          spelled = spelled(option)
          key = spelled || named(option)

          cond do
            spelled ->
              {one(name, "unit", unit, key), type}

            key in @types ->
              {unit, one(name, "type", type, key)}

            true ->
              raise ArgumentError,
                    "#{name} expects options among #{Enum.join(@units ++ @types, ", ")} " <>
                      "or a C type name, got #{describe(option)}"
          end
        end)

      {unit || :byte, type}
    end

    defp spelled(option) when is_binary(option) or (is_atom(option) and not is_nil(option)) do
      text = to_string(option)
      if String.valid?(text), do: @spelled[text |> String.downcase() |> String.trim()]
    end

    defp spelled(_option), do: nil

    defp scale(name, number, shift, type) when type in [nil, :f32, :f64] and is_float(number),
      do: {scaled(name, to(type || :f64, number), shift, type || :f64), type}

    defp scale(name, number, shift, type) when type in [:f32, :f64],
      do: {scaled(name, to(type, number), shift, type), type}

    defp scale(name, number, shift, type) when type in [nil, :big] do
      keep = if type, do: &trunc/1, else: &convert(name, &1, nil)
      number = keep.(number)

      cond do
        shift >= 0 and type -> {number <<< shift, type}
        shift >= 0 -> {wrap(number <<< shift, 64, false), type}
        (number &&& (1 <<< -shift) - 1) == 0 -> {number >>> -shift, type}
        true -> {number / (1 <<< -shift), nil}
      end
    end

    defp scale(_name, number, shift, type) do
      {bits, signed} = @ints[type]
      wide = max(max(bits, 32), if(abs(shift) > 30, do: 64, else: 32))
      signed = signed or bits < 32 or wide > bits
      number = wrap(to(type, number), wide, signed)
      factor = 1 <<< abs(shift)
      result = if shift < 0, do: Kernel.div(number, factor), else: number * factor
      {wrap(result, wide, signed), :"#{if signed, do: "s", else: "u"}#{wide}"}
    end

    defp scaled(name, number, shift, type) do
      to(type, number * :math.pow(2, shift))
    rescue
      ArithmeticError ->
        reraise ArgumentError, "#{name}: #{type} cannot hold the result", __STACKTRACE__
    end

    defp pick(name, options) do
      {base, type} =
        Enum.reduce(options, {nil, nil}, fn option, {base, type} ->
          key = named(option)

          cond do
            Keyword.has_key?(@bases, key) ->
              {one(name, "base", base, key), type}

            key in @types ->
              {base, one(name, "type", type, key)}

            true ->
              raise ArgumentError,
                    "#{name} expects options among #{Enum.join(@names, ", ")} or a C type name, " <>
                      "got #{describe(option)}"
          end
        end)

      {base || name, type}
    end

    defp type(name, option) do
      key = named(option)

      if key in @types do
        key
      else
        raise ArgumentError,
              "#{name} expects a type among #{Enum.join(@types, ", ")} or a C type name, " <>
                "got #{describe(option)}"
      end
    end

    defp named(option) when is_binary(option) or (is_atom(option) and not is_nil(option)) do
      text = to_string(option)

      if String.valid?(text) do
        words = text |> String.downcase() |> String.split()
        @known[Enum.join(words, " ")] || specifiers(Enum.frequencies(words))
      end
    end

    defp named(_option), do: nil

    defp specifiers(counts) do
      declared =
        map_size(counts) > 0 and
          Enum.all?(counts, fn {word, count} -> count <= Map.get(@words, word, 0) end) and
          not Enum.any?(@apart, fn group -> Enum.count(group, &Map.has_key?(counts, &1)) > 1 end)

      if declared do
        bits =
          Enum.find_value(@sizes, 32, fn {word, bits} -> Map.has_key?(counts, word) && bits end)

        Enum.find(
          @types,
          &(Atom.to_string(&1) == "#{if counts["unsigned"], do: "u", else: "s"}#{bits}")
        )
      end
    end

    defp one(_name, _kind, old, new) when old in [nil, new], do: new

    defp one(name, kind, old, new),
      do: raise(ArgumentError, "#{name} takes one #{kind}, got #{old} and #{new}")

    defp describe(value) do
      text = inspect(value, limit: 8, printable_limit: 64)
      if String.length(text) > 80, do: String.slice(text, 0, 77) <> "...", else: text
    end

    defp number(_name, value) when is_integer(value) or is_float(value), do: value
    defp number(_name, true), do: 1
    defp number(_name, false), do: 0
    defp number(_name, [char]) when is_integer(char) and char in 0..0x10FFFF, do: char

    defp number(name, text) when is_binary(text) do
      with true <- String.valid?(text), [char] <- String.to_charlist(text) do
        char
      else
        false ->
          raise ArgumentError, "#{name} expects valid UTF-8, got #{describe(text)}"

        chars ->
          raise ArgumentError,
                "#{name} expects a single character, got #{describe(text)} (#{length(chars)} code points)"
      end
    end

    defp number(name, other) do
      raise ArgumentError,
            "#{name} expects an integer, float, boolean, or single character, got #{describe(other)}"
    end

    defp convert(_name, number, nil) when is_float(number), do: number

    defp convert(name, number, nil) do
      if number < -(1 <<< 63) or number >= 1 <<< 64, do: wide(name)
      wrap(number, 64, false)
    end

    defp convert(_name, number, type), do: to(type, number)

    for {name, {bits, signed}} <- @ints do
      defp to(unquote(name), number),
        do: wrap(whole(unquote(name), number), unquote(bits), unquote(signed))
    end

    defp to(:big, number), do: trunc(number)
    defp to(:f64, number), do: real(:f64, number, 53)

    defp to(:f32, number) do
      <<float::float-32>> = <<real(:f32, number, 24)::float-32>>
      float
    rescue
      MatchError -> reraise ArgumentError, "f32 cannot hold #{describe(number)}", __STACKTRACE__
    end

    defp whole(_type, number) when is_integer(number), do: number

    defp whole(:u64, number) when number >= 0x8000000000000000,
      do: bxor(register(number - 0x8000000000000000, 64), 1 <<< 63)

    defp whole(type, number) when type in [:u32, :s64, :u64], do: register(number, 64)
    defp whole(_type, number), do: register(number, 32)

    defp register(number, bits) do
      whole = trunc(number)
      lowest = -(1 <<< (bits - 1))
      if whole >= lowest and whole < -lowest, do: whole, else: lowest
    end

    defp real(_type, number, _bits) when is_float(number), do: number

    defp real(type, number, bits) do
      size = abs(number)
      shift = max(length(Integer.digits(size, 2)) - bits, 0)
      quotient = size >>> shift
      rest = ((size - (quotient <<< shift)) <<< 1) + (quotient &&& 1)
      nearest = if rest > 1 <<< shift, do: quotient + 1, else: quotient
      if(number < 0, do: -1.0, else: 1.0) * (nearest <<< shift)
    rescue
      ArithmeticError ->
        reraise ArgumentError, "#{type} cannot hold #{describe(number)}", __STACKTRACE__
    end

    defp wrap(number, bits, signed) do
      low = number &&& (1 <<< bits) - 1
      if signed and low >= 1 <<< (bits - 1), do: low - (1 <<< bits), else: low
    end

    defp render(value, :size, _type) when is_integer(value), do: Integer.to_string(value)

    defp render(value, :size, _type) do
      <<_sign::1, exponent::11, fraction::52>> = <<value::float>>

      {whole, power} =
        if exponent == 0, do: {fraction, -1074}, else: {fraction + (1 <<< 52), exponent - 1075}

      scaled =
        if power < 0,
          do: Kernel.div(whole * 10 ** 20, 1 <<< -power),
          else: (whole <<< power) * 10 ** 20

      {digits, places} =
        scaled |> Integer.to_string() |> String.pad_leading(21, "0") |> String.split_at(-20)

      places =
        if String.starts_with?(places, "00000"), do: places, else: String.slice(places, 0, 5)

      cond do
        (scaled == 0 and value != 0) or abs(value) >= 1.0e21 ->
          inspect(value)

        String.trim_trailing(places, "0") == "" ->
          if(value < 0, do: "-", else: "") <> digits

        true ->
          if(value < 0, do: "-", else: "") <> digits <> "." <> String.trim_trailing(places, "0")
      end
    end

    defp render(value, base, _type) when is_float(value) do
      {radix, prefix} = @bases[base]
      fractional(value, radix, prefix)
    end

    defp render(value, base, type) do
      {radix, prefix} = @bases[base]

      if radix == 10 or type == :big do
        whole(value, radix, prefix)
      else
        {bits, _signed} = @ints[type || :u64]
        whole(value &&& (1 <<< bits) - 1, radix, prefix)
      end
    end

    defp wide(name) do
      IO.puts(
        :stderr,
        "#{name}: the value is wider than 64 bits and was cut to the low 64; pass :big to keep all of it"
      )
    end

    defp whole(number, radix, prefix) when number < 0, do: "-" <> whole(-number, radix, prefix)
    defp whole(number, radix, prefix), do: prefix <> Integer.to_string(number, radix)

    defp fractional(number, 10, _prefix), do: inspect(number)

    defp fractional(number, radix, prefix) do
      <<sign::1, _::63>> = <<number::float>>
      size = abs(number)
      whole = trunc(size)

      if(sign == 1, do: "-", else: "") <>
        whole(whole, radix, prefix) <> fraction(size - whole, radix, "")
    end

    defp fraction(rest, _radix, digits) when rest == 0,
      do: if(digits == "", do: "", else: "." <> digits)

    defp fraction(rest, radix, digits) do
      scaled = rest * radix
      digit = trunc(scaled)
      fraction(scaled - digit, radix, digits <> Integer.to_string(digit, radix))
    end
  end
end

import Bitwise
import IExHelpers

if Code.ensure_loaded?(IEx.Evaluator) and function_exported?(IEx.Evaluator, :parse, 3) and
     Map.has_key?(%Inspect.Opts{}, :inspect_fun) do
  IEx.configure(
    parser: {IExHelpers, :__parse__, []},
    inspect: [inspect_fun: &IExHelpers.__inspect__/2]
  )
end
