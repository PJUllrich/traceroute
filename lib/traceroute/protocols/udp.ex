defmodule Traceroute.Protocols.UDP do
  @moduledoc """
  Decodes a UDP datagram.
  """

  alias Traceroute.Protocols.UDP.Datagram

  @doc """
  Parses a UDP datagram.

  See: https://en.wikipedia.org/wiki/User_Datagram_Protocol#UDP_datagram_structure
  """
  @spec parse_datagram(binary()) :: Datagram.t()
  def parse_datagram(data) do
    <<source_port::16, dest_port::16, length::16, checksum::16, payload::binary>> = data

    %Datagram{
      source_port: source_port,
      dest_port: dest_port,
      length: length,
      checksum: checksum,
      data: payload
    }
  end
end
