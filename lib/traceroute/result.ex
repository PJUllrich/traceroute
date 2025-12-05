defmodule Traceroute.Result do
  @moduledoc """
  Defines the result types for traceroute operations.

  A traceroute produces a list of results, where each result can be one of:

    * `Hop` - An intermediate router responded with Time Exceeded
    * `DestinationReached` - The final destination was reached
    * `Timeout` - No response was received within the timeout period
    * `Error` - An error occurred during the probe

  ## Example

      iex> Traceroute.run("example.com")
      {:ok, [
        %Traceroute.Result.Hop{ttl: 1, time: 1234, ...},
        %Traceroute.Result.Hop{ttl: 2, time: 5678, ...},
        %Traceroute.Result.DestinationReached{ttl: 3, time: 9012, ...}
      ]}
  """

  alias __MODULE__.{DestinationReached, Error, Hop, Timeout}

  @type t :: Hop.t() | DestinationReached.t() | Timeout.t() | Error.t()

  @type trace :: [t()]

  @doc """
  Returns the TTL (hop number) for any result type.
  """
  @spec ttl(t()) :: pos_integer()
  def ttl(%Hop{ttl: ttl}), do: ttl
  def ttl(%DestinationReached{ttl: ttl}), do: ttl
  def ttl(%Timeout{ttl: ttl}), do: ttl
  def ttl(%Error{ttl: ttl}), do: ttl

  @doc """
  Returns the response time in microseconds, or `nil` for results without timing.
  """
  @spec time(t()) :: non_neg_integer() | nil
  def time(%Hop{time: time}), do: time
  def time(%DestinationReached{time: time}), do: time
  def time(%Timeout{}), do: nil
  def time(%Error{}), do: nil

  @doc """
  Returns the response time in milliseconds, or `nil` for results without timing.
  """
  @spec time_ms(t()) :: float() | nil
  def time_ms(%Hop{} = hop), do: Hop.time_ms(hop)
  def time_ms(%DestinationReached{} = dest), do: DestinationReached.time_ms(dest)
  def time_ms(%Timeout{}), do: nil
  def time_ms(%Error{}), do: nil

  @doc """
  Returns `true` if the result indicates the destination was reached.
  """
  @spec reached?(t()) :: boolean()
  def reached?(%DestinationReached{}), do: true
  def reached?(_), do: false

  @doc """
  Returns `true` if the result is a timeout.
  """
  @spec timeout?(t()) :: boolean()
  def timeout?(%Timeout{}), do: true
  def timeout?(_), do: false

  @doc """
  Returns `true` if the result is an error.
  """
  @spec error?(t()) :: boolean()
  def error?(%Error{}), do: true
  def error?(_), do: false

  @doc """
  Returns `true` if the result is a successful hop (including destination reached).
  """
  @spec success?(t()) :: boolean()
  def success?(%Hop{}), do: true
  def success?(%DestinationReached{}), do: true
  def success?(_), do: false
end
