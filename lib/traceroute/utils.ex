defmodule Traceroute.Utils do
  @moduledoc """
  Implements various helper functions.
  """

  alias Traceroute.Protocols

  @doc "Returns the IPv4 as Tuple for a given Domain."
  def get_ip(domain) when is_binary(domain) do
    {:ok, {:hostent, _, _, :inet, 4, [ip | _]}} = :inet.gethostbyname(String.to_charlist(domain))
    ip
  end

  @doc "Returns the domain for a given IP."
  def get_domain(ip) when is_tuple(ip) do
    with {:ok, {:hostent, domain, [], :inet, _version, _ip}} <- :inet_res.gethostbyaddr(ip) do
      {:ok, List.to_string(domain)}
    end
  end

  @doc "Converts an integer to an IPv4 tuple"
  def ipv4_tuple(ip) when is_integer(ip) do
    <<a::8, b::8, c::8, d::8>> = <<ip::32>>
    {a, b, c, d}
  end

  @doc """
  Checks if an ICMP response packet matches the expected identifier.

  This is used to filter ICMP responses when multiple sockets run in parallel,
  ensuring each socket only processes responses intended for its own request.

  ## Parameters

  * `reply_packet` - The raw ICMP response packet
  * `expected_id_or_port` - The identifier to match against:
  - For ICMP: the ICMP identifier (16-bit integer)
  - For UDP/TCP: the source port (16-bit integer)

  """
  def icmp_response_matches?(reply_packet, expected_id_or_port) do
    {_header, payload} = Protocols.IPv4.split_header(reply_packet)
    datagram = Protocols.ICMP.decode_datagram(payload)

    # IO.inspect({datagram, expected_id_or_port})

    case datagram do
      # Echo Reply - check identifier directly
      %{type: 0, reply: %{identifier: id}} ->
        id == expected_id_or_port

      # Time Exceeded with ICMP protocol - check embedded request datagram
      %{type: 11, reply: %{protocol: :icmp, request_datagram: %{id: id}}} ->
        id == expected_id_or_port

      # Destination Unreachable with ICMP protocol - check embedded request datagram
      %{type: 3, reply: %{protocol: :icmp, data: %{id: id}}} ->
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
