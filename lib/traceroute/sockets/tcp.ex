defmodule Traceroute.Sockets.TCP do
  @moduledoc """
  A GenServer that sends a TCP traceroute probe and waits for a response.

  Opens a TCP socket for sending probe packets and uses the ICMPConn singleton
  socket for receiving ICMP responses.

  The probe can complete in one of several ways:
  - TCP connection succeeds (reached destination)
  - TCP connection refused/reset (reached destination, port closed)
  - ICMP Time Exceeded received (intermediate hop responded)
  - Timeout (no response)

  ## Response Filtering

  When multiple TCP probes run in parallel, each probe registers with ICMPConn
  using its TCP source port. ICMPConn routes incoming ICMP responses to the
  correct probe process based on the source port in the embedded TCP header.
  """

  use GenServer

  alias __MODULE__
  alias Traceroute.Sockets.ICMPConn
  alias Traceroute.Utils

  require Logger

  @default_dest_port 80

  defstruct [
    :ip,
    :ip_protocol,
    :ttl,
    :timeout,
    :dest_port,
    :source_port,
    :tcp_socket,
    :socket_domain,
    :caller,
    :start_time,
    :timer_ref
  ]

  # Client API

  @doc """
  Sends a TCP probe to the given IP address with the specified TTL.

  Returns `{:ok, time_microseconds, result}` on success, or `{:error, reason}` on failure.

  ## Options
    - `:dest_port` - The destination port (default: 80)
  """
  def send(ip, ttl, timeout, ip_protocol, opts \\ []) do
    args = [ip: ip, ttl: ttl, timeout: timeout, ip_protocol: ip_protocol] ++ opts
    {:ok, pid} = start_link(args)
    GenServer.call(pid, :send_probe, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    state = %TCP{
      ip: Keyword.fetch!(args, :ip),
      ip_protocol: Keyword.fetch!(args, :ip_protocol),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      dest_port: Keyword.get(args, :dest_port, @default_dest_port),
      source_port: nil,
      tcp_socket: nil,
      socket_domain: nil,
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending TCP probe to #{:inet.ntoa(state.ip)}")
    %{domain: domain, protocol: protocol, ttl_opt: ttl_opt} = Utils.get_protocol_options(state.ip_protocol, :tcp)

    with {:ok, tcp_socket} <- :socket.open(domain, :stream, protocol),
         :ok <- :socket.setopt(tcp_socket, ttl_opt, state.ttl),
         # Bind to port 0 to let the OS assign an ephemeral port
         :ok <- :socket.bind(tcp_socket, %{family: domain, addr: Utils.any_addr(domain), port: 0}),
         {:ok, %{port: source_port}} <- :socket.sockname(tcp_socket) do
      state = %{
        state
        | tcp_socket: tcp_socket,
          socket_domain: domain,
          caller: from,
          source_port: source_port
      }

      # Ensure ICMPConn is running for this IP protocol
      _conn_pid = ICMPConn.get_or_start_conn(state.ip_protocol)

      # Register to receive ICMP responses for our source port
      case ICMPConn.register(state.ip_protocol, :tcp, source_port, self()) do
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
  def handle_info({:"$socket", socket, :select, _ref}, %{tcp_socket: socket} = state) do
    # The TCP socket is now ready to connect.
    state.tcp_socket |> :socket.connect() |> handle_connect(state)
  end

  def handle_info({:icmp_packet, source, reply_packet}, state) do
    Logger.debug("Received matching ICMP response for source port #{state.source_port}.")
    reply_and_stop({:ok, elapsed(state), {reply_packet, source}}, state)
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

    # Unregister from ICMPConn
    if state.source_port do
      ICMPConn.unregister(state.ip_protocol, :tcp, state.source_port)
    end

    :ok
  end

  # Private Functions

  defp start_probe(state) do
    dest_addr = %{family: state.socket_domain, addr: state.ip, port: state.dest_port}
    start_time = now()
    state = %{state | start_time: start_time}

    state.tcp_socket
    |> :socket.connect(dest_addr, :nowait)
    |> handle_connect(state)
  end

  defp handle_connect(result, state) do
    case result do
      # The TCP socket connected immediately. Unlikely, but possible on e.g. localhost.
      :ok ->
        handle_reached(state)

      # The TCP socket reached the destination but could not connect. We handle that as a `DestinationReached` event.
      {:error, reason} when reason in [:econnrefused, :econnreset] ->
        handle_reached(state)

      # The TCP socket is not ready to connect. We'll receive a `$socket` callback once it's ready.
      {:select, _select_info} ->
        timer_ref = Process.send_after(self(), :timeout, to_timeout(second: state.timeout))
        {:noreply, %{state | timer_ref: timer_ref}}

      {:error, reason} when reason in [:etimedout, :timeout, :ehostunreach, :enetunreach] ->
        Logger.debug("TCP connection error: #{reason}. Waiting for ICMP response.")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("TCP connection error: #{inspect(reason)}")
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
