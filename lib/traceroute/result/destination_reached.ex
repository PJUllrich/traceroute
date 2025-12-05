defmodule Traceroute.Result.DestinationReached do
  @moduledoc """
  Represents a successful traceroute result where the destination was reached.

  This result is returned when:
  - An ICMP Echo Reply is received from the target IP
  - An ICMP Destination Unreachable (Port Unreachable) is received for UDP probes
  - A TCP connection is established or reset by the target
  """

  defstruct [
    :ttl,
    :time,
    :addr,
    :domain
  ]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          time: non_neg_integer(),
          addr: :inet.ip4_address(),
          domain: String.t() | charlist() | nil
        }

  @doc """
  Creates a new DestinationReached result.

  ## Parameters

    * `ttl` - The TTL value at which the destination was reached (hop count)
    * `time` - Round-trip time in microseconds
    * `addr` - The IP address of the destination
    * `domain` - The resolved domain name (optional)
  """
  @spec new(pos_integer(), non_neg_integer(), :inet.ip4_address(), String.t() | charlist() | nil) ::
          t()
  def new(ttl, time, addr, domain \\ nil) do
    %__MODULE__{
      ttl: ttl,
      time: time,
      addr: addr,
      domain: domain
    }
  end

  @doc """
  Returns the round-trip time in milliseconds.
  """
  @spec time_ms(t()) :: float()
  def time_ms(%__MODULE__{time: time}) do
    Float.round(time / 1000, 3)
  end
end
