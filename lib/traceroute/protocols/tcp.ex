defmodule Traceroute.Protocols.TCP do
  @moduledoc """
  Parses TCP header for extracting information from ICMP error responses.

  When an ICMP error (Time Exceeded, Destination Unreachable) is received,
  it contains the first 8 bytes of the original TCP header, which includes
  the source and destination ports needed for request correlation.
  """

  alias Traceroute.Protocols.TCP.Header

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
