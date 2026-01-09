defmodule Traceroute.Sockets.ICMPConn do
  @moduledoc """
  Opens a singleton ICMP socket connection upon request and sends back received ICMP packets to the
  process that registered for its `protocol + port_or_identifier` combination.

  We should only ever have one open ICMP socket, because received ICMP packets are not routed to the
  ICMP sockets that sent them, unlike TCP or UDP sockets. That's why we open only a single socket and send&receive
  all ICMP packets through this socket. The routing of received packets happens in our application based on a
  combintation of protocol (e.g. `:tcp`, `:udp`, `:icmp`) and identifier (port or ICMP packet identifier)
  """

  use GenServer

  alias __MODULE__
  alias Traceroute.Utils

  require Logger

  # Delays the shutdown of the GenServer after the last subscriber process is unregistered
  # to prevent raceconditions of the last subscriber leaving and a new process trying to register.
  @shutdown_delay to_timeout(second: 5)

  defstruct [
    :socket,
    :ip_protocol,
    :registry
  ]

  @doc """
  Returns the `pid` of the `ICMPConn` for a given `ip_protocol: (:ipv4 | :ipv6)`.

  Starts the GenServer for the given `ip_protocol` if no process for the given protocol exists already.
  """
  def get_or_start_conn(ip_protocol) do
    ip_protocol
    |> build_name()
    |> GenServer.whereis()
    |> case do
      nil ->
        Logger.debug("ICMPConn was not started. Starting it for #{ip_protocol}.")
        {:ok, pid} = start_link(ip_protocol: ip_protocol)
        pid

      pid ->
        pid
    end
  end

  def start_link(args) do
    name = args |> Keyword.fetch!(:ip_protocol) |> build_name()
    GenServer.start(ICMPConn, args, name: name)
  end

  def send_packet(ip_protocol, ttl, packet, destination) do
    ip_protocol
    |> build_name()
    |> GenServer.call({:send, ttl, packet, destination})
  end

  def register(ip_protocol, protocol, identifier, pid) do
    ip_protocol
    |> build_name()
    |> GenServer.call({:register, protocol, identifier, pid})
  end

  def unregister(ip_protocol, protocol, identifier) do
    ip_protocol
    |> build_name()
    |> GenServer.call({:unregister, protocol, identifier})
  end

  # Callbacks

  @impl GenServer
  def init(opts) do
    ip_protocol = Keyword.fetch!(opts, :ip_protocol)

    {:ok, socket} =
      case ip_protocol do
        :ipv4 -> :socket.open(:inet, :dgram, :icmp)
        :ipv6 -> :socket.open(:inet6, :dgram, Utils.icmpv6_protocol())
      end

    send(self(), :receive)

    state = %ICMPConn{
      socket: socket,
      ip_protocol: ip_protocol,
      registry: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:receive, state) do
    case :socket.recvfrom(state.socket, [], :nowait) do
      # A message was immediately available.
      {:ok, {source, reply_packet}} ->
        handle_packet(source, reply_packet, state)
        send(self(), :receive)

      # No message was immediately available. Wait for the `$socket` callback
      # which is sent to this process when a message becomes available.
      {:select, _select_info} ->
        nil

      {:error, reason} ->
        Logger.error("Could not receive packet from ICMP socket #{state.ip_protocol}: #{inspect(reason)}")
        send(self(), :receive)
    end

    {:noreply, state}
  end

  # A message became available on the socket. Receive it.
  def handle_info({:"$socket", _socket, :select, _select_handle}, state) do
    send(self(), :receive)
    {:noreply, state}
  end

  # Unregister a registered process if it dies.
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    registry =
      state.registry
      |> Enum.filter(fn {_key, pid_value} -> pid_value != pid end)
      |> Map.new()

    if registry == %{} do
      schedule_terminate()
    end

    {:noreply, %{state | registry: registry}}
  end

  # Terminate the GenServer if no processes are registered anymore.
  def handle_info(:maybe_terminate, state) do
    if state.registry == %{} do
      :socket.close(state.socket)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call({:send, ttl, packet, destination}, _from, state) do
    %{ttl_opt: ttl_opt} = Utils.get_protocol_options(state.ip_protocol, :icmp)

    result =
      with :ok <- :socket.setopt(state.socket, ttl_opt, ttl) do
        :socket.sendto(state.socket, packet, destination)
      end

    {:reply, result, state}
  end

  def handle_call({:register, protocol, identifier, pid}, _from, state) do
    if Map.get(state.registry, {protocol, identifier}) do
      {:reply, {:error, :already_registered}, state}
    else
      Process.monitor(pid)
      registry = Map.put(state.registry, {protocol, identifier}, pid)
      {:reply, :ok, %{state | registry: registry}}
    end
  end

  def handle_call({:unregister, protocol, identifier}, _from, state) do
    registry = Map.delete(state.registry, {protocol, identifier})

    if registry == %{} do
      schedule_terminate()
    end

    {:reply, :ok, %{state | registry: registry}}
  end

  defp handle_packet(source, reply_packet, state) do
    Logger.debug("Received ICMP packet from #{:inet.ntoa(source.addr)}.")

    with {:ok, {protocol, identifier}} <- Utils.get_icmp_identifier(state.ip_protocol, reply_packet),
         {:ok, pid} <- get_registered_process(protocol, identifier, state) do
      send(pid, {:icmp_packet, source, reply_packet})
    else
      error ->
        Logger.warning("Could not send ICMP packet to registered process because #{inspect(error)}")
    end

    :ok
  end

  defp get_registered_process(protocol, identifier, state) do
    case Map.get(state.registry, {protocol, identifier}) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp schedule_terminate do
    Process.send_after(self(), :maybe_terminate, @shutdown_delay)
  end

  defp build_name(:ipv4), do: ICMPConn.IPv4
  defp build_name(:ipv6), do: ICMPConn.IPv6
end
