defmodule Traceroute.Sockets.Tcp do
  @moduledoc """
  Opens a TCP socket for sending probe packets and an ICMP socket for receiving responses.
  Uses synchronous socket operations.
  """

  @default_dest_port 80

  require Logger

  def send(ip, ttl, timeout, opts \\ []) do
    dest_port = Keyword.get(opts, :dest_port, @default_dest_port)
    dest_addr = %{family: :inet, addr: ip, port: dest_port}
    timeout_ms = to_timeout(second: timeout)

    with {:ok, tcp_socket} <- :socket.open(:inet, :stream, :tcp),
         :ok <- :socket.setopt(tcp_socket, {:ip, :ttl}, ttl),
         {:ok, icmp_socket} <- :socket.open(:inet, :dgram, :icmp) do
      try do
        {time, result} =
          :timer.tc(fn ->
            do_send(tcp_socket, icmp_socket, dest_addr, timeout_ms)
          end)

        with {:ok, data} <- result do
          {:ok, time, data}
        end
      after
        :socket.close(tcp_socket)
        :socket.close(icmp_socket)
      end
    end
  end

  defp do_send(tcp_socket, icmp_socket, dest_addr, timeout_ms) do
    start_time = now()
    # Try TCP connection synchronously with timeout
    case :socket.connect(tcp_socket, dest_addr, timeout_ms) do
      :ok ->
        Logger.debug("TCP Connection succeeded. We reached the destination.")
        {:ok, :reached}

      {:error, :econnrefused} ->
        Logger.debug("TCP Connection refused. We reached the destination (port closed).")
        {:ok, :reached}

      {:error, :econnreset} ->
        Logger.debug("TCP Connection reset. We reached the destination.")
        {:ok, :reached}

      {:error, reason} when reason in [:etimedout, :timeout, :ehostunreach, :enetunreach] ->
        # Connection timed out or host/network unreachable
        # Try to read ICMP response which should contain info about intermediate hop
        elapsed = now() - start_time
        remaining_timeout = max(0, timeout_ms - div(elapsed, 1000))
        Logger.debug("TCP Connection error #{reason}. Waiting for ICMP response.")

        read_icmp_response(icmp_socket, remaining_timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_icmp_response(icmp_socket, timeout_ms) do
    case :socket.recvfrom(icmp_socket, 0, timeout_ms) do
      {:ok, {_source, reply_packet}} ->
        {:ok, reply_packet}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp now, do: System.monotonic_time(:microsecond)
end
