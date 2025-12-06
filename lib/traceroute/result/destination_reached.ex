defmodule Traceroute.Result.DestinationReached do
  @moduledoc """
  Represents a successful traceroute result where the destination was reached.

  This result is returned when:
  - An ICMP Echo Reply is received from the target IP
  - An ICMP Destination Unreachable (Port Unreachable) is received for UDP probes
  - A TCP connection is established or reset by the target

  When multiple probes are sent in parallel, they are collected into a single
  DestinationReached result with all probes listed.

  ## Fields

    * `:ttl` - The TTL value at which the destination was reached (hop count)
    * `:probes` - List of individual probe results for this destination
  """

  alias Traceroute.Result.Probe

  defstruct [:ttl, :probes]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          probes: [Probe.t()]
        }

  @doc """
  Creates a new DestinationReached result from a TTL and a single probe or list of probes.
  """
  @spec new(pos_integer(), Probe.t() | [Probe.t()]) :: t()
  def new(ttl, probe_or_probes)

  def new(ttl, %Probe{} = probe) do
    %__MODULE__{
      ttl: ttl,
      probes: [probe]
    }
  end

  def new(ttl, probes) when is_list(probes) do
    %__MODULE__{
      ttl: ttl,
      probes: probes
    }
  end

  @doc """
  Returns the source address from the first probe, or nil if no probes.
  """
  @spec source_addr(t()) :: :inet.ip4_address() | nil
  def source_addr(%__MODULE__{probes: []}) do
    nil
  end

  def source_addr(%__MODULE__{probes: [probe | _]}) do
    probe.source_addr
  end
end
