defmodule Traceroute.Sockets.ICMP do
  @moduledoc """
  A GenServer that sends an ICMP traceroute probe and waits for a response.

  Uses the ICMPConn singleton socket to send ICMP packets and receive
  responses using asynchronous message handling.

  ## Response Filtering

  When multiple ICMP probes run in parallel, each probe registers with ICMPConn
  using its ICMP identifier. ICMPConn routes incoming ICMP responses to the
  correct probe process based on the identifier in the response packet.
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
    :caller,
    :start_time,
    :timer_ref,
    :identifier
  ]

  # Client API

  @doc """
  Sends an ICMP probe packet and waits for a response.

  Returns `{:ok, time_microseconds, reply_packet}` on success, or `{:error, reason}` on failure.

  ## Options
    - `:identifier` - The ICMP identifier used in the probe packet (required for response filtering)
  """
  def send(packet, ip, ttl, timeout, ip_protocol, opts \\ []) do
    args = [packet: packet, ip: ip, ttl: ttl, timeout: timeout, ip_protocol: ip_protocol] ++ opts
    {:ok, pid} = start_link(args)
    GenServer.call(pid, :send_probe, to_timeout(second: timeout + 1))
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
      ip_protocol: Keyword.fetch!(args, :ip_protocol),
      ttl: Keyword.fetch!(args, :ttl),
      timeout: Keyword.fetch!(args, :timeout),
      identifier: Keyword.fetch!(args, :identifier),
      caller: nil,
      start_time: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:send_probe, from, state) do
    Logger.debug("Sending ICMP probe to #{:inet.ntoa(state.ip)} with ID #{state.identifier} via #{state.ip_protocol}")

    # Ensure ICMPConn is running for this IP protocol
    _conn_pid = ICMPConn.get_or_start_conn(state.ip_protocol)

    # Register to receive ICMP responses for our identifier
    case ICMPConn.register(state.ip_protocol, :icmp, state.identifier, self()) do
      :ok ->
        state = %{state | caller: from}
        start_probe(state)

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:icmp_packet, source, reply_packet}, state) do
    Logger.debug("Received matching ICMP response for ID #{state.identifier}.")
    reply_and_stop({:ok, elapsed(state), {reply_packet, source}}, state)
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
    # Unregister from ICMPConn
    if state.identifier do
      ICMPConn.unregister(state.ip_protocol, :icmp, state.identifier)
    end

    :ok
  end

  # Private Functions

  defp start_probe(state) do
    %{domain: domain} = Utils.get_protocol_options(state.ip_protocol, :icmp)
    destination = %{family: domain, addr: state.ip}
    timeout = to_timeout(second: state.timeout)
    start_time = now()
    state = %{state | start_time: start_time}

    case ICMPConn.send_packet(state.ip_protocol, state.ttl, state.packet, destination) do
      :ok ->
        timer_ref = Process.send_after(self(), :timeout, timeout)
        {:noreply, %{state | timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("Could not send ICMP probe: #{inspect(reason)}")
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
