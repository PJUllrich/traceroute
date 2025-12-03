defmodule Traceroute.Sockets.Udp do
  @moduledoc """
  Opens a UDP socket for sending probe packets and an ICMP socket for receiving responses.

  This implements the UDP-based traceroute approach where:
  1. UDP packets are sent to high-numbered ports with increasing TTL values
  2. ICMP "Time Exceeded" or "Port Unreachable" messages are received on a separate ICMP socket
  3. The UDP socket triggers ICMP errors, but we read them from the ICMP socket

  This is how traditional traceroute works - it uses separate sockets for sending and receiving.
  """

  @default_dest_port 33_434

  @doc """
  Sends a UDP probe packet and waits for an ICMP response.

  Opens UDP and ICMP sockets, sends the packet, waits for a response,
  and closes the sockets before returning.

  ## Parameters
    - packet: The data to send
    - ip: The destination IP address as a tuple
    - ttl: Time-to-live value for the packet
    - timeout: Timeout in seconds to wait for a response

  ## Returns
    - `{:ok, time_microseconds, reply_packet}` on success
    - `{:error, reason}` on failure
  """
  def send(packet, ip, ttl, timeout, opts \\ []) do
    dest_port = Keyword.get(opts, :dest_port, @default_dest_port)

    with {:ok, udp_socket} <- :socket.open(:inet, :dgram, :udp),
         {:ok, icmp_socket} <- :socket.open(:inet, :dgram, :icmp) do
      try do
        do_send(packet, ip, ttl, timeout, udp_socket, icmp_socket, dest_port)
      after
        :socket.close(udp_socket)
        :socket.close(icmp_socket)
      end
    end
  end

  defp do_send(packet, ip, ttl, timeout, udp_socket, icmp_socket, dest_port) do
    dest_addr = %{family: :inet, addr: ip, port: dest_port}

    :ok = :socket.setopt(udp_socket, {:ip, :ttl}, ttl)

    {time, result} =
      :timer.tc(fn ->
        :socket.sendto(udp_socket, packet, dest_addr)
        :socket.recvfrom(icmp_socket, [], to_timeout(second: timeout))
      end)

    with {:ok, {_source, reply_packet}} <- result do
      {:ok, time, reply_packet}
    end
  end
end
