defmodule Traceroute.Sockets.ICMP do
  @moduledoc """
  A GenServer that sends an ICMP traceroute probe and waits for a response.

  Opens an ICMP datagram network socket, sends out ICMP packets, and receives
  responses using asynchronous socket operations with GenServer message handling.
  """

  defstruct [
    :packet,
    :ip,
    :ttl,
    :timeout,
    :socket,
    :caller,
    :start_time,
    :timer_ref
  ]

  alias __MODULE__

  use GenServer

  require Logger

  # Client API

  @doc """
  Sends an ICMP probe packet and waits for a response.

  Returns `{:ok, time_microseconds, reply_packet}` on success, or `{:error, reason}` on failure.
  """
  def send(packet, ip, ttl, timeout) do
    {:ok, pid} = start_link(packet: packet, ip: ip, ttl: ttl, timeout: timeout)
    GenServer.call(pid, :send_probe, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    state = %ICMP{
      packet: Keyword.fetch!(args, :packet),
      ip: Keyword.fetch!(args, :ip),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      socket: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending ICMP probe to #{:inet.ntoa(state.ip)}")

    with {:ok, socket} <- :socket.open(:inet, :dgram, :icmp),
         :ok <- :socket.setopt(socket, {:ip, :ttl}, state.ttl) do
      state = %ICMP{state | socket: socket, caller: from}
      start_probe(state)
    else
      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:"$socket", socket, :select, _ref}, %{socket: socket} = state) do
    receive_icmp(state)
  end

  def handle_info(:timeout, state) do
    Logger.debug("Probe timed out.")
    reply_and_stop({:error, :timeout}, state)
  end

  def handle_info(msg, state) do
    Logger.error("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.socket, do: :socket.close(state.socket)
    :ok
  end

  # Private Functions

  defp start_probe(state) do
    dest_addr = %{family: :inet, addr: state.ip}
    timeout = to_timeout(second: state.timeout)
    start_time = now()
    state = %ICMP{state | start_time: start_time}

    case :socket.sendto(state.socket, state.packet, dest_addr) do
      :ok ->
        timer_ref = Process.send_after(self(), :timeout, timeout)
        receive_icmp(%{state | timer_ref: timer_ref})

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  defp receive_icmp(state) do
    case :socket.recvfrom(state.socket, 0, :nowait) do
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
