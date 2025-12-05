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
  """

  defstruct [
    :packet,
    :ip,
    :ttl,
    :timeout,
    :dest_port,
    :udp_socket,
    :icmp_socket,
    :caller,
    :start_time,
    :timer_ref
  ]

  use GenServer

  require Logger

  alias __MODULE__

  @default_dest_port 33_434

  # Client API

  @doc """
  Sends a UDP probe packet and waits for an ICMP response.

  Returns `{:ok, time_microseconds, reply_packet}` on success, or `{:error, reason}` on failure.

  ## Options
    - `:dest_port` - The destination port (default: 33434)
  """
  def send(packet, ip, ttl, timeout, opts \\ []) do
    {:ok, pid} = start_link(packet: packet, ip: ip, ttl: ttl, timeout: timeout, opts: opts)
    GenServer.call(pid, :send_probe, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    opts = Keyword.get(args, :opts, [])

    state = %UDP{
      packet: Keyword.fetch!(args, :packet),
      ip: Keyword.fetch!(args, :ip),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      dest_port: Keyword.get(opts, :dest_port, @default_dest_port),
      udp_socket: nil,
      icmp_socket: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending UDP probe to #{:inet.ntoa(state.ip)}")

    with {:ok, udp_socket} <- :socket.open(:inet, :dgram, :udp),
         :ok <- :socket.setopt(udp_socket, {:ip, :ttl}, state.ttl),
         {:ok, icmp_socket} <- :socket.open(:inet, :dgram, :icmp) do
      state = %UDP{state | udp_socket: udp_socket, icmp_socket: icmp_socket, caller: from}
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
    dest_addr = %{family: :inet, addr: state.ip, port: state.dest_port}
    timeout = to_timeout(second: state.timeout)
    start_time = now()
    state = %UDP{state | start_time: start_time}

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
      {:ok, {_source, reply_packet}} ->
        Logger.debug("Received ICMP response.")
        reply_and_stop({:ok, elapsed(state), reply_packet}, state)

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
