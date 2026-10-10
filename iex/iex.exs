defmodule IExHelpers do
  @moduledoc false

  def hex(value), do: show(:hex, value, 16, "0x")
  def bin(value), do: show(:bin, value, 2, "0b")
  def oct(value), do: show(:oct, value, 8, "0o")

  defp show(name, value, radix, prefix) do
    number = to_number(name, value)
    IO.puts(format(number, radix, prefix))
    number
  end

  defp to_number(_name, n) when is_integer(n) or is_float(n), do: n
  defp to_number(_name, true), do: 1
  defp to_number(_name, false), do: 0
  defp to_number(_name, [c]) when is_integer(c) and c in 0..0x10FFFF, do: c

  defp to_number(name, s) when is_binary(s) do
    case String.next_codepoint(s) do
      {<<c::utf8>>, ""} ->
        c

      _ ->
        raise ArgumentError,
              "#{name}/1 expects a single character, got: #{inspect(s)} " <>
                "(#{length(String.to_charlist(s))} code points)"
    end
  rescue
    UnicodeConversionError ->
      raise ArgumentError, "#{name}/1 expects valid UTF-8, got: #{inspect(s)}"
  end

  defp to_number(name, other) do
    raise ArgumentError,
          "#{name}/1 expects an integer, float, boolean, or single character, got: #{inspect(other)}"
  end

  defp format(n, radix, prefix) when n < 0, do: "-" <> format(-n, radix, prefix)
  defp format(n, radix, prefix) when is_integer(n), do: prefix <> Integer.to_string(n, radix)

  defp format(n, radix, prefix) when is_float(n) do
    whole = trunc(n)

    case fraction(n - whole, radix, []) do
      "" -> prefix <> Integer.to_string(whole, radix)
      digits -> prefix <> Integer.to_string(whole, radix) <> "." <> digits
    end
  end

  defp fraction(f, _radix, acc) when f == 0, do: acc |> Enum.reverse() |> Enum.join()

  defp fraction(f, radix, acc) do
    scaled = f * radix
    digit = trunc(scaled)
    fraction(scaled - digit, radix, [Integer.to_string(digit, radix) | acc])
  end
end

import Bitwise
import IExHelpers
