defmodule Traceroute.Protocols.UDP.Datagram do
  @moduledoc """
  Represents a parsed UDP datagram.

  See: https://en.wikipedia.org/wiki/User_Datagram_Protocol#UDP_datagram_structure
  """

  defstruct [:source_port, :dest_port, :length, :checksum, :data]

  @type t :: %__MODULE__{
          source_port: non_neg_integer(),
          dest_port: non_neg_integer(),
          length: non_neg_integer(),
          checksum: non_neg_integer(),
          data: binary()
        }
end
