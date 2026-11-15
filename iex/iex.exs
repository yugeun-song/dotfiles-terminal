unless Code.ensure_loaded?(IExHelpers) do
  defmodule IExHelpers do
    @moduledoc false
    import Bitwise

    @bases [bin: {2, "0b"}, oct: {8, "0o"}, dec: {10, ""}, hex: {16, "0x"}]
    @ints for bits <- [8, 16, 32, 64],
              {sign, signed} <- [u: false, s: true],
              do: {:"#{sign}#{bits}", {bits, signed}}
    @floats [f32: 32, f64: 64]
    @types Keyword.keys(@ints) ++ Keyword.keys(@floats) ++ [:big]
    @names Keyword.keys(@bases) ++ @types
    @shown {__MODULE__, :shown}

    for name <- @names do
      def unquote(name)(), do: unquote(name)
    end

    for {name, _} <- @bases do
      def unquote(name)(value), do: show(unquote(name), value, [])
      def unquote(name)(value, option), do: show(unquote(name), value, [option])
      def unquote(name)(value, option, other), do: show(unquote(name), value, [option, other])
    end

    for name <- @types do
      def unquote(name)(value), do: cast(unquote(name), number(unquote(name), value))
    end

    def __reset__, do: Process.put(@shown, :none)

    def __parse__(input, opts, state) do
      with {:ok, forms, state} <- IEx.Evaluator.parse(input, opts, state) do
        {:ok, reset(forms), state}
      end
    end

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
      {:ok, render(name, term, base, type)}
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
      if type, do: cast(type, number)

      case Process.get(@shown) do
        nil -> IO.puts(render(name, number, base, type))
        _ -> Process.put(@shown, {name, base, type})
      end

      number
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
                    "#{name} expects options among #{Enum.join(@names, ", ")}, got #{describe(option)}"
          end
        end)

      {base || name, type}
    end

    defp named(option) when is_binary(option) or (is_atom(option) and not is_nil(option)) do
      text = option |> to_string() |> String.downcase()
      Enum.find(@names, &(Atom.to_string(&1) == text))
    end

    defp named(_option), do: nil

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

    for {name, {bits, signed}} <- @ints do
      defp cast(unquote(name), number), do: wrap(trunc(number), unquote(bits), unquote(signed))
    end

    for {name, size} <- @floats do
      defp cast(unquote(name), number) do
        <<float::float-size(unquote(size))>> = <<number::float-size(unquote(size))>>
        float
      rescue
        _ in [ArgumentError, MatchError] ->
          raise ArgumentError, "#{unquote(name)} cannot hold #{describe(number)}"
      end
    end

    defp cast(:big, number), do: trunc(number)

    defp wrap(number, bits, signed) do
      low = number &&& (1 <<< bits) - 1
      if signed and low >= 1 <<< (bits - 1), do: low - (1 <<< bits), else: low
    end

    defp render(name, value, base, type) do
      {radix, prefix} = @bases[base]
      value = if type, do: cast(type, value), else: value

      cond do
        is_float(value) ->
          real(value, radix, prefix)

        type == :big ->
          whole(value, radix, prefix)

        true ->
          {bits, signed} = @ints[type || :u64]
          if is_nil(type) and (value < -(1 <<< 63) or value >= 1 <<< 64), do: wide(name)
          value = wrap(value, bits, signed)

          if radix == 10,
            do: Integer.to_string(value),
            else: whole(value &&& (1 <<< bits) - 1, radix, prefix)
      end
    end

    defp wide(name) do
      IO.puts(
        :stderr,
        "#{name}: the value is wider than 64 bits and only the low 64 are shown; pass :big to see all of it"
      )
    end

    defp whole(number, radix, prefix) when number < 0, do: "-" <> whole(-number, radix, prefix)
    defp whole(number, radix, prefix), do: prefix <> Integer.to_string(number, radix)

    defp real(number, 10, _prefix), do: inspect(number)

    defp real(number, radix, prefix) do
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
