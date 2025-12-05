defmodule Traceroute.Protocols.ICMP.RequestDatagram do
  @moduledoc """
  Represents the original ICMP request datagram embedded in ICMP error responses.

  When a router or destination sends back an ICMP error (like Time Exceeded or
  Destination Unreachable), it includes the header and first bytes of the original
  packet that triggered the error. This struct captures that data for correlation.
  """

  defstruct [
    :type,
    :code,
    :checksum,
    :id,
    :sequence,
    :rest
  ]

  @type t :: %__MODULE__{
          type: non_neg_integer(),
          code: non_neg_integer(),
          checksum: binary(),
          id: non_neg_integer(),
          sequence: non_neg_integer(),
          rest: binary()
        }

  @doc """
  Parses the original request datagram from an ICMP error response payload.
  """
  @spec parse(binary()) :: t()
  def parse(data) do
    <<
      type::8,
      code::8,
      checksum::binary-size(2),
      id::16,
      sequence::16,
      rest::binary
    >> = data

    %__MODULE__{
      type: type,
      code: code,
      checksum: checksum,
      id: id,
      sequence: sequence,
      rest: rest
    }
  end
end
