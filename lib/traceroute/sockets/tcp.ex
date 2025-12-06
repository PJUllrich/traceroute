defmodule Traceroute.Sockets.TCP do
  @moduledoc """
  A GenServer that sends a TCP traceroute probe and waits for a response.

  Opens a TCP socket for sending probe packets and an ICMP socket for receiving responses.
  Uses asynchronous socket operations with GenServer message handling.

  The probe can complete in one of several ways:
  - TCP connection succeeds (reached destination)
  - TCP connection refused/reset (reached destination, port closed)
  - ICMP Time Exceeded received (intermediate hop responded)
  - Timeout (no response)

  ## Response Filtering

  When multiple TCP sockets run in parallel, each socket may receive ICMP
  responses intended for other sockets. This module filters responses by
  matching the TCP source port in the ICMP error message against the source
  port used by this socket.
  """

  use GenServer

  alias Traceroute.Utils

  require Logger

  @default_dest_port 80

  # Client API

  @doc """
  Sends a TCP probe to the given IP address with the specified TTL.

  Returns `{:ok, time_microseconds, result}` on success, or `{:error, reason}` on failure.

  ## Options
    - `:dest_port` - The destination port (default: 80)
  """
  def send(ip, ttl, timeout, opts \\ []) do
    {:ok, pid} = start_link(ip: ip, ttl: ttl, timeout: timeout, opts: opts)
    GenServer.call(pid, :send_probe, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    state = %{
      ip: Keyword.fetch!(args, :ip),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      dest_port: Keyword.get(args, :opts, []) |> Keyword.get(:dest_port, @default_dest_port),
      source_port: nil,
      tcp_socket: nil,
      icmp_socket: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending TCP probe to #{:inet.ntoa(state.ip)}")

    with {:ok, tcp_socket} <- :socket.open(:inet, :stream, :tcp),
         :ok <- :socket.setopt(tcp_socket, {:ip, :ttl}, state.ttl),
         # Bind to port 0 to let the OS assign an ephemeral port
         :ok <- :socket.bind(tcp_socket, %{family: :inet, addr: {0, 0, 0, 0}, port: 0}),
         {:ok, %{port: source_port}} <- :socket.sockname(tcp_socket),
         {:ok, icmp_socket} <- :socket.open(:inet, :dgram, :icmp) do
      state = %{
        state
        | tcp_socket: tcp_socket,
          icmp_socket: icmp_socket,
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
  def handle_info({:"$socket", socket, :select, _ref}, %{tcp_socket: socket} = state) do
    handle_tcp_ready(state)
  end

  def handle_info({:"$socket", socket, :select, _ref}, %{icmp_socket: socket} = state) do
    receive_icmp(state)
  end

  def handle_info(:timeout, state) do
    Logger.debug("Probe timed out.")
    reply_and_stop({:error, :timeout}, state)
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.tcp_socket, do: :socket.close(state.tcp_socket)
    if state.icmp_socket, do: :socket.close(state.icmp_socket)
    :ok
  end

  # Private Functions

  defp start_probe(state) do
    dest_addr = %{family: :inet, addr: state.ip, port: state.dest_port}
    start_time = now()
    state = %{state | start_time: start_time}

    case :socket.connect(state.tcp_socket, dest_addr, :nowait) do
      :ok ->
        handle_reached(state)

      {:error, reason} when reason in [:econnrefused, :econnreset] ->
        handle_reached(state)

      {:select, _select_info} ->
        timer_ref = Process.send_after(self(), :timeout, to_timeout(second: state.timeout))
        receive_icmp(%{state | timer_ref: timer_ref})

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  defp handle_tcp_ready(state) do
    case :socket.connect(state.tcp_socket) do
      :ok ->
        handle_reached(state)

      {:error, reason} when reason in [:econnrefused, :econnreset] ->
        handle_reached(state)

      {:error, reason} when reason in [:etimedout, :timeout, :ehostunreach, :enetunreach] ->
        Logger.debug("TCP connection error: #{reason}. Waiting for ICMP response.")
        {:noreply, state}

      {:error, reason} ->
        Logger.debug("TCP connection error: #{inspect(reason)}")
        reply_and_stop({:error, reason}, state)
    end
  end

  defp receive_icmp(state) do
    case :socket.recvfrom(state.icmp_socket, 0, :nowait) do
      {:ok, {_source, reply_packet}} ->
        if Utils.icmp_response_matches?(reply_packet, state.source_port) do
          Logger.debug("Received matching ICMP response.")
          reply_and_stop({:ok, elapsed(state), reply_packet}, state)
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

  defp handle_reached(state) do
    Logger.debug("TCP connection reached destination.")
    reply_and_stop({:ok, elapsed(state), :reached}, state)
  end

  defp reply_and_stop(reply, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    GenServer.reply(state.caller, reply)
    {:stop, :normal, state}
  end

  defp elapsed(state), do: now() - state.start_time

  defp now, do: System.monotonic_time(:microsecond)
end
