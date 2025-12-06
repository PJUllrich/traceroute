defmodule Traceroute.Utils do
  @moduledoc """
  Implements various helper functions.
  """

  alias Traceroute.Protocols
  alias Traceroute.Protocols.ICMP.Unparsed

  require Logger

  @doc "Returns the IPv4 or IPv6 address as Tuple for a given IP Protocol and Domain."
  def get_ip(_ip_protocol, ip) when is_tuple(ip), do: ip
  def get_ip(:ipv4, domain) when is_binary(domain), do: get_ipv4(domain)
  def get_ip(:ipv6, domain) when is_binary(domain), do: get_ipv6(domain)

  @doc "Returns the IPv4 as Tuple for a given Domain."
  def get_ipv4(domain) when is_binary(domain) do
    {:ok, {:hostent, _, _, :inet, 4, [ip | _]}} = :inet.gethostbyname(String.to_charlist(domain), :inet)
    ip
  end

  @doc "Returns the IPv6 as Tuple for a given Domain."
  def get_ipv6(domain) when is_binary(domain) do
    {:ok, {:hostent, _, _, :inet6, 16, [ip | _]}} = :inet.gethostbyname(String.to_charlist(domain), :inet6)
    ip
  end

  @doc "Returns the domain for a given IP."
  def get_domain(ip) when is_tuple(ip) do
    with {:ok, {:hostent, domain, [], _inet_or_inet6, _version, _ip}} <- :inet_res.gethostbyaddr(ip) do
      {:ok, domain}
    end
  end

  @doc "Returns the socket domain, protocol, and ttl option for an IP protocol."
  def get_protocol_options(:ipv4, protocol) when protocol in [:icmp, :udp, :tcp] do
    %{domain: :inet, protocol: protocol, ttl_opt: {:ip, :ttl}}
  end

  def get_protocol_options(:ipv6, protocol) do
    protocol =
      case protocol do
        :icmp -> :"IPV6-ICMP"
        :udp -> :udp
        :tcp -> :tcp
      end

    %{domain: :inet6, protocol: protocol, ttl_opt: {:ipv6, :unicast_hops}}
  end

  @doc "Returns the any address for a given socket domain."
  def any_addr(:inet), do: {0, 0, 0, 0}
  def any_addr(:inet6), do: {0, 0, 0, 0, 0, 0, 0, 0}

  @doc "Converts an integer to an IPv4 tuple"
  def ipv4_tuple(ip) when is_integer(ip) do
    <<a::8, b::8, c::8, d::8>> = <<ip::32>>
    {a, b, c, d}
  end

  @doc "Converts an integer to an IPv6 tuple"
  def ipv6_tuple(ip) when is_integer(ip) do
    <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> = <<ip::128>>
    {a, b, c, d, e, f, g, h}
  end

  @doc """
  Splits an ICMP reply packet into IP header and payload.

  For IPv6, an optional source address can be provided (from the socket's recvfrom result)
  since ICMPv6 DGRAM sockets strip the IPv6 header.
  """
  def split_reply_packet(ip_protocol, reply_packet, source \\ nil)

  def split_reply_packet(:ipv4, reply_packet, _source) do
    Protocols.IPv4.split_header(reply_packet)
  end

  def split_reply_packet(:ipv6, reply_packet, source) do
    Protocols.IPv6.split_header(reply_packet, source)
  end

  @doc """
  Checks if an ICMP response packet matches the expected identifier.

  This is used to filter ICMP responses when multiple sockets run in parallel,
  ensuring each socket only processes responses intended for its own request.

  ## Parameters

  * `ip_protocol` - Whether the packet was sent through `:ipv4` or `:ipv6`
  * `reply_packet` - The raw ICMP response packet
  * `expected_id_or_port` - The identifier to match against:
  - For ICMP: the ICMP identifier (16-bit integer)
  - For UDP/TCP: the source port (16-bit integer)

  """
  def icmp_response_matches?(ip_protocol, reply_packet, expected_id_or_port) do
    {_header, payload} = split_reply_packet(ip_protocol, reply_packet)
    datagram = Protocols.ICMP.decode_datagram(payload, ip_protocol)

    # IO.inspect({datagram, expected_id_or_port})

    case datagram do
      # Ignore unparsed packets
      %Protocols.ICMP{reply: %Unparsed{}} ->
        Logger.warning("Ignoring unparsed packet: #{inspect(datagram)}")
        false

      # Echo Reply - check identifier directly
      %{type: 0, reply: %{identifier: id}} ->
        id == expected_id_or_port

      # Time Exceeded with ICMP protocol - check embedded request datagram
      %{type: 11, reply: %{protocol: protocol, request_datagram: %{id: id}}}
      when protocol in [:icmp, :icmpv6] ->
        id == expected_id_or_port

      # Destination Unreachable with ICMP protocol - check embedded request datagram
      %{type: 3, reply: %{protocol: protocol, data: %{id: id}}}
      when protocol in [:icmp, :icmpv6] ->
        id == expected_id_or_port

      # Time Exceeded with UDP protocol - check embedded UDP source port
      %{type: 11, reply: %{protocol: :udp, request_datagram: %{source_port: port}}} ->
        port == expected_id_or_port

      # Destination Unreachable with UDP protocol - check embedded UDP source port
      %{type: 3, reply: %{protocol: :udp, data: %{source_port: port}}} ->
        port == expected_id_or_port

      # Time Exceeded with TCP protocol - check embedded TCP source port
      %{type: 11, reply: %{protocol: :tcp, request_datagram: %{source_port: port}}} ->
        port == expected_id_or_port

      # Destination Unreachable with TCP protocol - check embedded TCP source port
      %{type: 3, reply: %{protocol: :tcp, data: %{source_port: port}}} ->
        port == expected_id_or_port

      # Unknown or unparseable - reject to be safe
      _ ->
        false
    end
  end
end
