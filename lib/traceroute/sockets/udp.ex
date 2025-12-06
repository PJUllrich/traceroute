defmodule Traceroute.Sockets.UDP do
  @moduledoc """
  A GenServer that sends a UDP traceroute probe and waits for a response.

  Opens a UDP socket for sending probe packets and an ICMP socket for receiving responses.
  Uses asynchronous socket operations with GenServer message handling.

  This implements the UDP-based traceroute approach where:
  1. UDP packets are sent to high-numbered ports with increasing TTL values
  2. ICMP "Time Exceeded" or "Port Unreachable" messages are received on a separate ICMP socket
  3. The UDP socket triggers ICMP errors, but we read them from the ICMP socket

  If the probe reaches an open port, it will be accepted silently and no response is sent. That means that the probe will result in a `timeout`. You can try to increment the UDP port with every retry probe to prevent this.

  ## Response Filtering

  When multiple UDP sockets run in parallel, each socket may receive ICMP
  responses intended for other sockets. This module filters responses by
  matching the UDP source port in the ICMP error message against the source
  port used by this socket.
  """

  use GenServer

  alias __MODULE__
  alias Traceroute.Utils

  require Logger

  defstruct [
    :packet,
    :ip,
    :ip_protocol,
    :ttl,
    :timeout,
    :dest_port,
    :source_port,
    :udp_socket,
    :icmp_socket,
    :socket_domain,
    :caller,
    :start_time,
    :timer_ref
  ]

  @default_dest_port 33_434

  # Client API

  @doc """
  Sends a UDP probe packet and waits for an ICMP response.

  Returns `{:ok, time_microseconds, reply_packet}` on success, or `{:error, reason}` on failure.

  ## Options
    - `:dest_port` - The destination port (default: 33434)
  """
  def send(packet, ip, ttl, timeout, ip_protocol, opts \\ []) do
    args = [packet: packet, ip: ip, ttl: ttl, timeout: timeout, ip_protocol: ip_protocol] ++ opts
    {:ok, pid} = start_link(args)
    GenServer.call(pid, :send_probe, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    state = %UDP{
      packet: Keyword.fetch!(args, :packet),
      ip: Keyword.fetch!(args, :ip),
      ip_protocol: Keyword.fetch!(args, :ip_protocol),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      dest_port: Keyword.get(args, :dest_port, @default_dest_port),
      source_port: nil,
      udp_socket: nil,
      icmp_socket: nil,
      socket_domain: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending UDP probe to #{:inet.ntoa(state.ip)}")
    %{domain: domain, protocol: protocol, ttl_opt: ttl_opt} = Utils.get_protocol_options(state.ip_protocol, :udp)
    %{protocol: icmp_protocol} = Utils.get_protocol_options(state.ip_protocol, :icmp)

    with {:ok, udp_socket} <- :socket.open(domain, :dgram, protocol),
         :ok <- :socket.setopt(udp_socket, ttl_opt, state.ttl),
         # Bind to port 0 to let the OS assign an ephemeral port
         :ok <- :socket.bind(udp_socket, %{family: domain, addr: Utils.any_addr(domain), port: 0}),
         {:ok, %{port: source_port}} <- :socket.sockname(udp_socket),
         {:ok, icmp_socket} <- :socket.open(domain, :dgram, icmp_protocol) do
      state = %{
        state
        | udp_socket: udp_socket,
          icmp_socket: icmp_socket,
          socket_domain: domain,
          caller: from,
          source_port: source_port
      }

      start_probe(state)
    else
      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:"$socket", socket, :select, _ref}, %{icmp_socket: socket} = state) do
    receive_icmp(state)
  end

  def handle_info(:timeout, state) do
    Logger.debug("UDP Probe timed out.")
    reply_and_stop({:error, :timeout}, state)
  end

  def handle_info(msg, state) do
    Logger.error("Unexpected message received by UDP socket: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.udp_socket, do: :socket.close(state.udp_socket)
    if state.icmp_socket, do: :socket.close(state.icmp_socket)
    :ok
  end

  # Private Functions

  defp start_probe(state) do
    dest_addr = %{family: state.socket_domain, addr: state.ip, port: state.dest_port}
    timeout = to_timeout(second: state.timeout)
    start_time = now()
    state = %{state | start_time: start_time}

    case :socket.sendto(state.udp_socket, state.packet, dest_addr) do
      :ok ->
        timer_ref = Process.send_after(self(), :timeout, timeout)
        receive_icmp(%{state | timer_ref: timer_ref})

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  defp receive_icmp(state) do
    case :socket.recvfrom(state.icmp_socket, 0, :nowait) do
      {:ok, {source, reply_packet}} ->
        if Utils.icmp_response_matches?(state.ip_protocol, reply_packet, state.source_port) do
          Logger.debug("Received matching ICMP response.")
          reply_and_stop({:ok, elapsed(state), {reply_packet, source}}, state)
        else
          Logger.debug("Ignoring ICMP response with non-matching source port.")
          {:noreply, state}
        end

      {:select, _select_info} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.debug("Error reading ICMP response: #{inspect(reason)}")
        reply_and_stop({:error, reason}, state)
    end
  end

  defp reply_and_stop(reply, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    GenServer.reply(state.caller, reply)
    {:stop, :normal, state}
  end

  defp elapsed(state), do: now() - state.start_time

  defp now, do: System.monotonic_time(:microsecond)
end
