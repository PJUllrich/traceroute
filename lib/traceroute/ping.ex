defmodule Traceroute.Ping do
  @moduledoc """
  Sends a Ping request to a domain and returns the request time and response data.
  """

  alias Traceroute.Protocols
  alias Traceroute.Protocols.ICMP
  alias Traceroute.Result.{DestinationReached, Probe}
  alias Traceroute.Sockets
  alias Traceroute.Utils

  @doc """
  Send a Ping request to a given domain.

  Returns `{:ok, result}` where result is one of:
    * `%Probe{}` - An intermediate router responded
    * `%DestinationReached{}` - The destination was reached

  Or `{:error, reason}` on failure.
  """
  def run(domain_or_ip, opts) do
    default_opts = [
      protocol: :icmp,
      ttl: 128,
      timeout: 15,
      ip_protocol: :ipv4
    ]

    opts = default_opts |> Keyword.merge(opts) |> Map.new()
    ip = Utils.get_ip(opts.ip_protocol, domain_or_ip)

    do_run(opts.protocol, ip, opts)
  end

  defp do_run(:icmp, ip, opts) do
    # Echo Request: type 8 for ICMPv4, type 128 for ICMPv6
    type = if opts.ip_protocol == :ipv6, do: 128, else: 8
    code = 0
    id = :rand.uniform(65_535)
    sequence = 1
    payload = "ping"

    type
    |> Protocols.ICMP.encode_datagram(code, id, sequence, payload)
    |> Sockets.ICMP.send(ip, opts.ttl, opts.timeout, opts.ip_protocol, identifier: id)
    |> parse_response(ip, opts.ttl, opts.ip_protocol)
  end

  defp do_run(:udp, ip, opts) do
    "probe"
    |> Sockets.UDP.send(ip, opts.ttl, opts.timeout, opts.ip_protocol)
    |> parse_response(ip, opts.ttl, opts.ip_protocol)
  end

  defp do_run(:tcp, ip, opts) do
    ip
    |> Sockets.TCP.send(opts.ttl, opts.timeout, opts.ip_protocol)
    |> parse_response(ip, opts.ttl, opts.ip_protocol)
  end

  # TCP reached destination (connection established or reset)
  defp parse_response({:ok, time, :reached}, ip, ttl, _ip_protocol) do
    domain = resolve_domain(ip)
    header = %{source_addr: ip, source_domain: domain}
    probe = Probe.new(ttl, time, header, nil)
    {:ok, DestinationReached.new(ttl, probe)}
  end

  # Got an ICMP response packet (with source address from socket)
  defp parse_response({:ok, time, {reply_packet, source}}, ip, ttl, ip_protocol) do
    {header, payload} = Utils.split_reply_packet(ip_protocol, reply_packet, source)
    icmp = Protocols.ICMP.decode_datagram(payload, ip_protocol)

    result = build_result(icmp, ip, ttl, time, header)
    {:ok, result}
  end

  defp parse_response(error, _ip, _ttl, _ip_protocol), do: error

  # Echo Reply from destination - we've reached it
  defp build_result(%ICMP{reply: %ICMP.EchoReply{}} = icmp, ip, ttl, time, header) do
    # If the reply came from our target IP, it's definitely reached
    if header.source_addr == ip do
      probe = Probe.new(ttl, time, header, icmp)
      DestinationReached.new(ttl, probe)
    else
      # Reply from somewhere else (shouldn't happen normally)
      Probe.new(ttl, time, header, icmp)
    end
  end

  # Destination Unreachable (Port Unreachable) - destination reached via UDP
  defp build_result(%ICMP{reply: %ICMP.DestinationUnreachable{}} = icmp, _ip, ttl, time, header) do
    probe = Probe.new(ttl, time, header, icmp)
    DestinationReached.new(ttl, probe)
  end

  # Time Exceeded - intermediate probe
  defp build_result(%ICMP{reply: %ICMP.TimeExceeded{}} = icmp, _ip, ttl, time, header) do
    Probe.new(ttl, time, header, icmp)
  end

  # Any other ICMP response - treat as a probe
  defp build_result(%ICMP{} = icmp, _ip, ttl, time, header) do
    Probe.new(ttl, time, header, icmp)
  end

  defp resolve_domain(ip) do
    case Utils.get_domain(ip) do
      {:ok, domain} -> domain
      _error -> :inet.ntoa(ip)
    end
  end
end
