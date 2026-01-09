defmodule Traceroute.Sockets.UDP do
  @moduledoc """
  A GenServer that sends a UDP traceroute probe and waits for a response.

  Opens a UDP socket for sending probe packets and uses the ICMPConn singleton
  socket for receiving ICMP responses.

  This implements the UDP-based traceroute approach where:
  1. UDP packets are sent to high-numbered ports with increasing TTL values
  2. ICMP "Time Exceeded" or "Port Unreachable" messages are received via ICMPConn
  3. The UDP socket triggers ICMP errors, which ICMPConn routes back to this process

  If the probe reaches an open port, it will be accepted silently and no response is sent. That means that the probe will result in a `timeout`. You can try to increment the UDP port with every retry probe to prevent this.

  ## Response Filtering

  When multiple UDP probes run in parallel, each probe registers with ICMPConn
  using its UDP source port. ICMPConn routes incoming ICMP responses to the
  correct probe process based on the source port in the embedded UDP header.
  """

  use GenServer

  alias __MODULE__
  alias Traceroute.Sockets.ICMPConn
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
      socket_domain: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    %{domain: domain, protocol: protocol, ttl_opt: ttl_opt} = Utils.get_protocol_options(state.ip_protocol, :udp)

    with {:ok, udp_socket} <- :socket.open(domain, :dgram, protocol),
         :ok <- :socket.setopt(udp_socket, ttl_opt, state.ttl),
         # Bind to port 0 to let the OS assign an ephemeral port
         :ok <- :socket.bind(udp_socket, %{family: domain, addr: Utils.any_addr(domain), port: 0}),
         {:ok, %{port: source_port}} <- :socket.sockname(udp_socket) do
      state = %{
        state
        | udp_socket: udp_socket,
          socket_domain: domain,
          caller: from,
          source_port: source_port
      }

      Logger.debug("Sending UDP probe to #{:inet.ntoa(state.ip)} from #{source_port}")

      # Ensure ICMPConn is running for this IP protocol
      _conn_pid = ICMPConn.get_or_start_conn(state.ip_protocol)

      # Register to receive ICMP responses for our source port
      case ICMPConn.register(state.ip_protocol, :udp, source_port, self()) do
        :ok ->
          start_probe(state)

        {:error, reason} ->
          {:stop, :normal, {:error, reason}, state}
      end
    else
      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:icmp_packet, source, reply_packet}, state) do
    Logger.debug("Received matching ICMP response for UDP source port #{state.source_port}.")
    reply_and_stop({:ok, elapsed(state), {reply_packet, source}}, state)
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

    # Unregister from ICMPConn
    if state.source_port do
      ICMPConn.unregister(state.ip_protocol, :udp, state.source_port)
    end

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
        {:noreply, %{state | timer_ref: timer_ref}}

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
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
