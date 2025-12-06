defmodule Traceroute.Protocols.IPv6 do
  @moduledoc """
  Implements decoding IPv6 Headers.
  """

  alias Traceroute.Protocols.IPv6.Header
  alias Traceroute.Utils

  @doc """
  Parses an IPv6 packet and separates the header from the payload.

  When receiving from an ICMPv6 DGRAM socket, the kernel strips the IPv6 header
  and delivers only the ICMPv6 payload. In this case, the packet will NOT start
  with version 6, so we return a minimal header struct and treat the entire
  packet as payload.

  When receiving a full IPv6 packet (e.g., from a raw socket), we parse the
  complete header.

  ## Parameters

  - `packet` - The raw packet data
  - `source` - Optional source address map from socket's recvfrom result (e.g., `%{addr: {ipv6_tuple}, ...}`)
  """
  def split_header(packet, source \\ nil) do
    # Check if this packet starts with IPv6 version (first 4 bits = 6)
    case packet do
      <<6::4, _rest::bitstring>> ->
        parse_full_ipv6_header(packet)

      _ ->
        # ICMPv6 DGRAM sockets strip the IPv6 header, so the packet starts
        # directly with the ICMPv6 message. Return a minimal header.
        # The source address is obtained from the socket's recvfrom result.
        {source_addr, source_domain} = resolve_source(source)

        header = %Header{
          version: 6,
          ds: 0,
          ecn: 0,
          flow_label: 0,
          payload_length: byte_size(packet),
          # ICMPv6
          next_header: 58,
          max_hops: 0,
          source_addr: source_addr,
          source_domain: source_domain,
          destination_addr: nil
        }

        {header, packet}
    end
  end

  defp parse_full_ipv6_header(packet) do
    <<
      # IPv6 Headers always start with the version 6
      6::4,
      ds::6,
      ecn::2,
      flow_label::20,
      payload_length::16,
      next_header::8,
      max_hops::8,
      source_addr::128,
      destination_addr::128,
      payload::bytes
    >> = packet

    payload = remove_next_header_from_payload(next_header, payload)

    source_addr = Utils.ipv6_tuple(source_addr)

    source_domain =
      case Traceroute.Utils.get_domain(source_addr) do
        {:ok, domain} -> domain
        _error -> :inet.ntoa(source_addr)
      end

    destination_addr = Utils.ipv6_tuple(destination_addr)

    header = %Header{
      version: 6,
      ds: ds,
      ecn: ecn,
      flow_label: flow_label,
      payload_length: payload_length,
      next_header: next_header,
      max_hops: max_hops,
      source_addr: source_addr,
      source_domain: source_domain,
      destination_addr: destination_addr
    }

    {header, payload}
  end

  # Resolves source address from socket recvfrom result

  defp resolve_source(%{addr: source_addr}) when is_tuple(source_addr) do
    source_domain =
      case Utils.get_domain(source_addr) do
        {:ok, domain} -> domain
        _error -> :inet.ntoa(source_addr)
      end

    {source_addr, source_domain}
  end

  defp resolve_source(_), do: {nil, nil}

  # Hop-by-Hop Option
  defp remove_next_header_from_payload(0, payload) do
    <<
      _header_type::8,
      header_length::8,
      _options::bytes-size(6),
      _padding::bytes-size(header_length),
      payload::bytes
    >> = payload

    payload
  end

  # Routing Option
  defp remove_next_header_from_payload(43, payload) do
    <<
      _header_type::8,
      header_length::8,
      _routing_type::8,
      _segments_left::8,
      _data::bytes-size(6),
      _padding::bytes-size(header_length),
      payload::bytes
    >> = payload

    payload
  end

  # Fragment Option
  defp remove_next_header_from_payload(44, payload) do
    <<
      _header_type::8,
      _reserved_1::8,
      _offset::13,
      _reserved_2::2,
      _m_flag::1,
      _identification::bytes-size(4),
      payload::bytes
    >> = payload

    payload
  end

  # Other options not implemented since we shouldn't encounter them when running a traceroute.
end
