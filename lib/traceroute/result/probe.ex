defmodule Traceroute.Result.Probe do
  @moduledoc """
  Represents a single probe response in a traceroute.

  A probe is recorded when a router along the path responds with an ICMP
  Time Exceeded message after the packet's TTL reaches zero.

  ## Fields

    * `:ttl` - The TTL value used for this probe (hop number)
    * `:time` - Round-trip time in microseconds
    * `:source_addr` - IP address of the responding router as a tuple
    * `:source_domain` - Hostname of the responding router (or IP string if DNS lookup fails)
    * `:reply` - The parsed ICMP response struct
  """

  alias Traceroute.Protocols.ICMP

  defstruct [
    :ttl,
    :time,
    :source_addr,
    :source_domain,
    :reply
  ]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          time: non_neg_integer(),
          source_addr: :inet.ip_address(),
          source_domain: String.t(),
          reply: ICMP.t()
        }

  @doc """
  Creates a new Probe from the TTL, response time, IPv4 header, and ICMP data.
  """
  @spec new(pos_integer(), non_neg_integer(), map(), ICMP.t()) :: t()
  def new(ttl, time, ip_header, icmp) do
    %__MODULE__{
      ttl: ttl,
      time: time,
      source_addr: ip_header.source_addr,
      source_domain: ip_header.source_domain,
      reply: icmp
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
