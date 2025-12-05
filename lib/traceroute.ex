defmodule Traceroute do
  @moduledoc """
  Performs a traceroute request to a given domain.
  """

  require Logger

  alias Traceroute.Ping
  alias Traceroute.Result
  alias Traceroute.Result.{DestinationReached, Error, Hop, Timeout}
  alias Traceroute.Utils

  @doc """
  Run a traceroute on a given domain.

  ## Options
    * `protocol: :icmp|:udp|:tcp` (default `:icmp`). Which protocol to use for sending the pings.
    * `max_hops: 20` (default: 20). After how many hops traceroute should abort.
    * `max_retries: 3` (default: 3). How often to retry each hop before moving to the next hop.
    * `timeout: 1`. How long to wait for a response in seconds.
    * `print_output: true|false`. Whether to print the output to STDOUT or not.

  ## Returns
    * `{:ok, trace}` if destination is reached, where trace is a list of `Result.t()`.
    * `{:error, :max_hops_exceeded, trace}` if max hops are exceeded.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, Result.trace()} | {:error, :max_hops_exceeded, Result.trace()}
  def run(domain, opts \\ []) when is_binary(domain) do
    default_opts = [
      protocol: :icmp,
      max_hops: 20,
      max_retries: 3,
      timeout: 1,
      print_output: true
    ]

    opts = default_opts |> Keyword.merge(opts) |> Map.new()

    ip = Utils.get_ip(domain)

    do_run(ip, 1, opts.max_hops, opts.max_retries, [], opts)
  end

  defp do_run(_ip, _ttl, 0 = _max_hops, _retries, trace, _opts) do
    {:error, :max_hops_exceeded, Enum.reverse(trace)}
  end

  defp do_run(ip, ttl, max_hops, retries, trace, opts) do
    case Ping.run(ip, ttl: ttl, timeout: opts.timeout, protocol: opts.protocol) do
      {:ok, %DestinationReached{} = result} ->
        print(result, opts)
        {:ok, Enum.reverse([result | trace])}

      {:ok, %Hop{} = hop} ->
        print(hop, opts)
        do_run(ip, ttl + 1, max_hops - 1, 0, [hop | trace], opts)

      {:error, :timeout} ->
        handle_timeout(ip, ttl, max_hops, retries, trace, opts)

      {:error, reason} ->
        error = Error.new(ttl, reason)
        print(error, opts)
        do_run(ip, ttl + 1, max_hops - 1, 0, [error | trace], opts)
    end
  end

  defp handle_timeout(ip, ttl, max_hops, retries, trace, opts) do
    stars = "*" |> List.duplicate(min(retries + 1, opts.max_retries)) |> Enum.join(" ")

    if retries < opts.max_retries do
      print_timeout_retry(ttl, stars, opts)
      do_run(ip, ttl, max_hops, retries + 1, trace, opts)
    else
      timeout = Timeout.new(ttl, opts.max_retries)
      print_timeout_final(ttl, stars, opts)
      do_run(ip, ttl + 1, max_hops - 1, 0, [timeout | trace], opts)
    end
  end

  # Printing helpers

  defp print(result, opts) do
    if opts.print_output do
      do_print(result)
    end
  end

  defp print_timeout_retry(ttl, stars, opts) do
    if opts.print_output do
      IO.write("\r#{ttl} #{stars}")
    end
  end

  defp print_timeout_final(ttl, stars, opts) do
    if opts.print_output do
      IO.write("\r#{ttl} #{stars}\n")
    end
  end

  defp do_print(%Hop{} = hop) do
    time_ms = Hop.time_ms(hop)
    IO.write("\r#{hop.ttl} #{hop.source_domain} (#{format_addr(hop.source_addr)}) #{time_ms}ms\n")
  end

  defp do_print(%DestinationReached{} = dest) do
    time_ms = DestinationReached.time_ms(dest)

    case dest.domain do
      nil ->
        IO.write("\r#{dest.ttl} #{format_addr(dest.addr)} #{time_ms}ms\n")

      domain ->
        IO.write("\r#{dest.ttl} #{domain} (#{format_addr(dest.addr)}) #{time_ms}ms\n")
    end
  end

  defp do_print(%Error{} = error) do
    IO.write("\r#{error.ttl} #{inspect(error.reason)}\n")
  end

  defp format_addr(addr) when is_tuple(addr), do: :inet.ntoa(addr)
  defp format_addr(addr), do: addr
end
