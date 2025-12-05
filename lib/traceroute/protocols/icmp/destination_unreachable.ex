defmodule Traceroute.Protocols.ICMP.DestinationUnreachable do
  @moduledoc """
  Represents an ICMP Destination Unreachable message (Type 3).

  This message is returned when a packet cannot be delivered to its destination.
  In traceroute, a "Port Unreachable" (code 3) indicates the packet has reached
  the destination server but the target port is not open - which is the expected
  behavior signaling the end of the route.

  See: https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol#Destination_unreachable
  """

  defstruct [:protocol, :data]

  @type protocol :: :icmp | :tcp | :udp

  @type t :: %__MODULE__{
          protocol: protocol(),
          data: map() | binary()
        }
end
