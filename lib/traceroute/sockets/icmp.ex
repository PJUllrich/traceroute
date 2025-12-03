defmodule Traceroute.Sockets.Icmp do
  @moduledoc """
  Opens an ICMP datagram network socket and sends out ICMP packets through it.

  Written with the help of https://github.com/hauleth/gen_icmp/blob/master/src/inet_icmp.erl
  """

  @doc """
  Opens a socket, sends an ICMP packet, waits for a response, and closes the socket.

  Returns `{:ok, time_in_microseconds, reply_packet}` on success, or `{:error, reason}` on failure.
  """
  def send(packet, ip, ttl, timeout) do
    with {:ok, socket} <- :socket.open(:inet, :dgram, :icmp) do
      try do
        do_send(socket, packet, ip, ttl, timeout)
      after
        :socket.close(socket)
      end
    end
  end

  defp do_send(socket, packet, ip, ttl, timeout) do
    dest_addr = %{family: :inet, addr: ip}

    :ok = :socket.setopt(socket, {:ip, :ttl}, ttl)

    {time, result} =
      :timer.tc(fn ->
        :socket.sendto(socket, packet, dest_addr)
        :socket.recvfrom(socket, [], to_timeout(second: timeout))
      end)

    with {:ok, {_source, reply_packet}} <- result do
      {:ok, time, reply_packet}
    end
  end
end
