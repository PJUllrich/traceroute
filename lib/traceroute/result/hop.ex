defmodule Traceroute.Result.Hop do
  @moduledoc """
  Represents an intermediate hop in a traceroute.

  A hop is recorded when a router along the path responds with an ICMP
  Time Exceeded message after the packet's TTL reaches zero.

  ## Fields

    * `:ttl` - The TTL value used for this probe (hop number)
    * `:time` - Round-trip time in microseconds
    * `:source_addr` - IP address of the responding router as a tuple
    * `:source_domain` - Hostname of the responding router (or IP string if DNS lookup fails)
    * `:icmp` - The parsed ICMP response struct
  """

  defstruct [
    :ttl,
    :time,
    :source_addr,
    :source_domain,
    :icmp
  ]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          time: non_neg_integer(),
          source_addr: :inet.ip4_address(),
          source_domain: String.t() | charlist(),
          icmp: Traceroute.Protocols.ICMP.t()
        }

  @doc """
  Creates a new Hop from the TTL, response time, IPv4 header, and ICMP data.
  """
  @spec new(pos_integer(), non_neg_integer(), map(), Traceroute.Protocols.ICMP.t()) :: t()
  def new(ttl, time, ipv4_header, icmp) do
    %__MODULE__{
      ttl: ttl,
      time: time,
      source_addr: ipv4_header.source_addr,
      source_domain: ipv4_header.source_domain,
      icmp: icmp
    }
  end

  @doc """
  Returns the round-trip time formatted in milliseconds.
  """
  @spec time_ms(t()) :: float()
  def time_ms(%__MODULE__{time: time}) do
    Float.round(time / 1000, 3)
  end
end
