defmodule Traceroute.Protocols.ICMP do
  @moduledoc """
  Implements the encoding and decoding of ICMP and ICMPv6 packets.

  See: https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol
  See: https://en.wikipedia.org/wiki/ICMPv6
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

  @doc """
  Decodes an IPv4 or IPv6 ICMP datagram and its reply packet.
  """
  @spec decode_datagram(binary(), atom()) :: t()
  def decode_datagram(payload, ip_protocol) do
    <<type::8, code::8, checksum::16, rest::binary>> = payload

    type = if ip_protocol == :ipv4, do: type, else: normalize_icmpv6_type(type)
    reply = parse_reply(type, code, ip_protocol, rest)

    %__MODULE__{
      type: type,
      code: code,
      checksum: <<checksum::16>>,
      reply: reply
    }
  end

  # ICMPv6 type numbers (different from IPv4 ICMP)
  # https://en.wikipedia.org/wiki/ICMPv6#Types
  #
  # Maps ICMPv6 types to their IPv4 ICMP equivalents where applicable.
  #
  # ICMP message types with IPv4 equivalents
  # Echo Reply -> 0
  defp normalize_icmpv6_type(129), do: 0
  # Destination Unreachable -> 3
  defp normalize_icmpv6_type(1), do: 3
  # Packet Too Big -> Destination Unreachable (fragmentation needed)
  defp normalize_icmpv6_type(2), do: 3
  # Time Exceeded -> 11
  defp normalize_icmpv6_type(3), do: 11
  # Other ICMP message types that we don't parse (but might still receive)
  defp normalize_icmpv6_type(type), do: type

  # Echo Reply (Type 0, Code 0)
  # The 4 bytes after checksum are: identifier (16 bits) + sequence (16 bits)
  defp parse_reply(0, 0, _ip_protocol, <<identifier::16, sequence::16, data::binary>>) do
    %EchoReply{
      identifier: identifier,
      sequence: sequence,
      data: data
    }
  end

  # Time Exceeded (Type 11)
  # The 4 bytes after checksum are: unused (32 bits), then the original IP header + data
  defp parse_reply(11, _code, ip_protocol, <<_unused::32, payload::binary>>) do
    {protocol, data} = extract_original_packet(ip_protocol, payload)

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

  # Destination Unreachable (Type 3, all codes)
  # Common codes:
  #   0 - Network Unreachable
  #   1 - Host Unreachable
  #   3 - Port Unreachable
  #   4 - Fragmentation Needed and DF was Set (Path MTU Discovery)
  #   13 - Communication Administratively Prohibited
  # The 4 bytes after checksum are: unused (16 bits) + next-hop MTU (16 bits), then original packet
  # Note: next-hop MTU is only meaningful for code 4, but the format is the same for all codes
  defp parse_reply(3, _code, ip_protocol, <<_unused::16, _next_hop_mtu::16, payload::binary>>) do
    {protocol, data} = extract_original_packet(ip_protocol, payload)

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

  # Fallback for unhandled ICMP types - return as Unparsed instead of crashing
  defp parse_reply(type, code, _ip_protocol, payload) do
    %Unparsed{type: type, code: code, payload: payload}
  end

  # Extracts the original packet from an ICMP error response.
  # Returns the protocol and the data portion after the IPv4 header.
  defp extract_original_packet(:ipv4, payload) do
    <<_ihl_version::4, ihl::4, rest::binary>> = payload
    <<ipv4_header::binary-size(ihl * 4 - 1), data::binary>> = rest
    <<_::binary-size(8), protocol_num::8, _rest::binary>> = ipv4_header

    protocol = parse_protocol(protocol_num)

    {protocol, data}
  end

  # Extracts the original packet from an ICMPv6 error response.
  # Returns the protocol and the data portion after the IPv6 header.
  # IPv6 header is always 40 bytes (no variable IHL like IPv4).
  defp extract_original_packet(:ipv6, payload) do
    case payload do
      <<
        _version_traffic_flow::32,
        _payload_length::16,
        next_header::8,
        _hop_limit::8,
        _source_addr::128,
        _dest_addr::128,
        data::binary
      >> ->
        protocol = parse_protocol(next_header)
        {protocol, data}

      # If we can't parse the full IPv6 header, return what we have
      _ ->
        {:unknown, payload}
    end
  end

  # Maps IPv4 protocol numbers to atoms
  # https://en.wikipedia.org/wiki/IPv4#Protocol
  # https://en.wikipedia.org/wiki/List_of_IP_protocol_numbers
  defp parse_protocol(1), do: :icmp
  defp parse_protocol(6), do: :tcp
  defp parse_protocol(17), do: :udp
  defp parse_protocol(58), do: :icmp
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
