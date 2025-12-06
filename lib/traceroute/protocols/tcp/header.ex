defmodule Traceroute.Protocols.TCP.Header do
  @moduledoc """
  Represents a parsed TCP header (first 8 bytes).

  In ICMP error responses, only the first 8 bytes of the original packet
  are guaranteed to be included, which contains:
  - Source Port (2 bytes)
  - Destination Port (2 bytes)
  - Sequence Number (4 bytes)

  See: https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_segment_structure
  """

  defstruct [:source_port, :dest_port, :sequence_number]

  @type t :: %__MODULE__{
          source_port: non_neg_integer(),
          dest_port: non_neg_integer(),
          sequence_number: non_neg_integer()
        }
end
