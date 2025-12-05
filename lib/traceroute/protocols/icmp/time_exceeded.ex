defmodule Traceroute.Protocols.ICMP.TimeExceeded do
  @moduledoc """
  Represents an ICMP Time Exceeded message (Type 11).

  This message is sent by a router when a packet's TTL reaches zero,
  which is the core mechanism that makes traceroute work.

  ## Fields

    * `:protocol` - The protocol of the original packet (`:icmp`, `:tcp`, or `:udp`)
    * `:request_datagram` - The original datagram that triggered this response

  ## Codes

    * Code 0: TTL expired in transit
    * Code 1: Fragment reassembly time exceeded
  """

  alias Traceroute.Protocols.ICMP.RequestDatagram

  defstruct [:protocol, :request_datagram]

  @type t :: %__MODULE__{
          protocol: :icmp | :tcp | :udp | non_neg_integer(),
          request_datagram: RequestDatagram.t()
        }
end
