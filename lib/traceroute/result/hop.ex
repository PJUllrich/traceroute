defmodule Traceroute.Result.Hop do
  @moduledoc """
  Represents a hop in a traceroute, containing one or more probe results.

  A hop groups all probe responses for a given TTL value. When multiple
  probes are sent in parallel, they are collected into a single hop.

  ## Fields

    * `:ttl` - The TTL value used for this hop (hop number)
    * `:probes` - List of probe results for this hop
  """

  alias Traceroute.Result.Probe

  defstruct [:ttl, :probes]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          probes: [Probe.t()]
        }

  @doc """
  Creates a new Hop from a TTL and a single probe or list of probes.
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
