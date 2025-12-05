defmodule Traceroute.Protocols.TCP do
  @moduledoc """
  Parses TCP header for extracting information from ICMP error responses.

  When an ICMP error (Time Exceeded, Destination Unreachable) is received,
  it contains the first 8 bytes of the original TCP header, which includes
  the source and destination ports needed for request correlation.
  """

  defmodule Header do
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

  @doc """
  Parses the first 8 bytes of a TCP header.

  This is sufficient for extracting the source port, destination port,
  and sequence number from ICMP error responses.

  ## TCP Header Structure (first 8 bytes):
      0                   1                   2                   3
      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |          Source Port          |       Destination Port        |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |                        Sequence Number                        |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  @spec parse_header(binary()) :: Header.t()
  def parse_header(data) do
    <<source_port::16, dest_port::16, sequence_number::32, _rest::binary>> = data

    %Header{
      source_port: source_port,
      dest_port: dest_port,
      sequence_number: sequence_number
    }
  end
end
