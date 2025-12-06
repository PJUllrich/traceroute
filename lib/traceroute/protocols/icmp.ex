defmodule Traceroute.Protocols.ICMP do
  @moduledoc """
  Implements the encoding and decoding of ICMP packets.

  See: https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol
  """

  import Bitwise

  alias Traceroute.Protocols

  alias Traceroute.Protocols.ICMP.{
    DestinationUnreachable,
    EchoReply,
    RequestDatagram,
    TimeExceeded,
    Unparsed
  }

  defstruct [
    :type,
    :code,
    :checksum,
    :reply
  ]

  @type reply ::
          EchoReply.t()
          | TimeExceeded.t()
          | DestinationUnreachable.t()
          | Unparsed.t()

  @type t :: %__MODULE__{
          type: non_neg_integer(),
          code: non_neg_integer(),
          checksum: binary(),
          reply: reply()
        }

  @doc """
  Encodes an ICMP datagram which consists of a header and data section.

  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      Type     |      Code     |           Checksum          |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |     Rest of Header - Varies based on ICMP type and code     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                             Data                            |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

  """
  @spec encode_datagram(
          type :: non_neg_integer(),
          code :: non_neg_integer(),
          id :: non_neg_integer(),
          sequence :: non_neg_integer(),
          payload :: binary()
        ) :: binary()
  def encode_datagram(type, code, id, sequence, payload) do
    header = <<type, code, 0::16, id::16, sequence::16>>

    checksum = checksum(header <> payload)

    <<
      # Line 1
      type::8,
      code::8,
      checksum::binary-size(2),
      # Line 2
      id::16,
      sequence::16,
      # Line 3
      payload::binary
    >>
  end

  @spec decode_datagram(binary()) :: t()
  def decode_datagram(payload) do
    <<type::8, code::8, checksum::16, rest::binary>> = payload

    reply = parse_reply(type, code, rest)

    %__MODULE__{
      type: type,
      code: code,
      checksum: <<checksum::16>>,
      reply: reply
    }
  end

  # Echo Reply (Type 0, Code 0)
  # The 4 bytes after checksum are: identifier (16 bits) + sequence (16 bits)
  defp parse_reply(0, 0, <<identifier::16, sequence::16, data::binary>>) do
    %EchoReply{
      identifier: identifier,
      sequence: sequence,
      data: data
    }
  end

  # Time Exceeded (Type 11)
  # The 4 bytes after checksum are: unused (32 bits), then the original IP header + data
  defp parse_reply(11, _code, <<_unused::32, payload::binary>>) do
    {protocol, data} = extract_original_packet(payload)

    parsed_data =
      case protocol do
        :icmp -> RequestDatagram.parse(data)
        :udp -> Protocols.UDP.parse_datagram(data)
        :tcp -> Protocols.TCP.parse_header(data)
        _ -> data
      end

    %TimeExceeded{
      protocol: protocol,
      request_datagram: parsed_data
    }
  end

  # Destination Unreachable - Port Unreachable (Type 3, Code 3)
  # The 4 bytes after checksum are: unused (16 bits) + next-hop MTU (16 bits), then original packet
  defp parse_reply(3, 3, <<_unused::16, _next_hop_mtu::16, payload::binary>>) do
    {protocol, data} = extract_original_packet(payload)

    parsed_data =
      case protocol do
        :icmp -> RequestDatagram.parse(data)
        :udp -> Protocols.UDP.parse_datagram(data)
        :tcp -> Protocols.TCP.parse_header(data)
        _ -> data
      end

    %DestinationUnreachable{
      protocol: protocol,
      data: parsed_data
    }
  end

  # Fallback for unhandled ICMP types
  defp parse_reply(type, code, payload) do
    %Unparsed{
      type: type,
      code: code,
      payload: payload
    }
  end

  # Extracts the original packet from an ICMP error response.
  # Returns the protocol and the data portion after the IPv4 header.
  defp extract_original_packet(payload) do
    <<_ihl_version::4, ihl::4, rest::binary>> = payload
    <<ipv4_header::binary-size(ihl * 4 - 1), data::binary>> = rest
    <<_::binary-size(8), protocol_num::8, _rest::binary>> = ipv4_header

    protocol = parse_protocol(protocol_num)

    {protocol, data}
  end

  # Maps IPv4 protocol numbers to atoms
  # https://en.wikipedia.org/wiki/IPv4#Protocol
  defp parse_protocol(1), do: :icmp
  defp parse_protocol(6), do: :tcp
  defp parse_protocol(17), do: :udp
  defp parse_protocol(n), do: n

  @spec checksum(binary()) :: binary()
  def checksum(data), do: checksum(data, 0)

  defp checksum(<<val::16, rest::binary>>, sum), do: checksum(rest, sum + val)
  # Pad the data if it's not divisible by 16 bits
  defp checksum(<<val::8>>, sum), do: checksum(<<val, 0>>, sum)

  defp checksum(<<>>, sum) do
    <<left::16, right::16>> = <<sum::32>>
    <<bnot(left + right)::big-integer-size(16)>>
  end
end
