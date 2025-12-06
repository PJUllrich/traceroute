defmodule Traceroute do
  @moduledoc """
  Performs a traceroute request to a given domain.
  """

  alias Traceroute.Ping
  alias Traceroute.Result
  alias Traceroute.Result.{DestinationReached, Error, Hop, Probe, Timeout}
  alias Traceroute.Utils

  require Logger

  @doc """
  Run a traceroute on a given domain.

  ## Options
    * `protocol: :icmp|:udp|:tcp` (default `:icmp`). Which protocol to use for sending the pings.
    * `max_hops: 20` (default: 20). After how many hops traceroute should abort.
    * `max_retries: 3` (default: 3). How often to retry each hop before moving to the next hop.
    * `timeout: 1`. How long to wait for a response in seconds.
    * `print_output: true|false`. Whether to print the output to STDOUT or not.
    * `probes: 1` (default: 1). Number of probes to send in parallel for each TTL.

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
      print_output: true,
      probes: 1
    ]

    opts = default_opts |> Keyword.merge(opts) |> Map.new()

    ip = Utils.get_ip(domain)

    do_run(ip, 1, opts.max_hops, opts.max_retries, [], opts)
  end

  defp do_run(_ip, _ttl, 0 = _max_hops, _retries, trace, _opts) do
    {:error, :max_hops_exceeded, Enum.reverse(trace)}
  end

  defp do_run(ip, ttl, max_hops, retries, trace, opts) do
    results = run_parallel_probes(ip, ttl, opts)
    combined_result = combine_probe_results(results, ttl, opts)

    case combined_result do
      {:ok, :destination_reached, dest} ->
        print(dest, opts)
        {:ok, Enum.reverse([dest | trace])}

      {:ok, :hop, hop} ->
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

  # Small delay between probes to avoid router ICMP rate limiting (in ms)
  @probe_delay_ms 50

  defp run_parallel_probes(ip, ttl, opts) do
    1..opts.probes//1
    |> Task.async_stream(
      fn probe_num ->
        # Stagger probe sends to avoid ICMP rate limiting on routers
        if probe_num > 1, do: Process.sleep((probe_num - 1) * @probe_delay_ms)
        Ping.run(ip, ttl: ttl, timeout: opts.timeout, protocol: opts.protocol)
      end,
      timeout: (opts.timeout + 1) * 1000 + opts.probes * @probe_delay_ms,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
    end)
  end

  defp combine_probe_results(results, ttl, opts) do
    # Separate results by type
    {destinations, probes, timeouts, errors} =
      Enum.reduce(results, {[], [], [], []}, fn result, {dests, probes, timeouts, errs} ->
        case result do
          {:ok, %DestinationReached{} = dest} -> {[dest | dests], probes, timeouts, errs}
          {:ok, %Probe{} = probe} -> {dests, [probe | probes], timeouts, errs}
          {:error, :timeout} -> {dests, probes, [:timeout | timeouts], errs}
          {:error, reason} -> {dests, probes, timeouts, [reason | errs]}
        end
      end)

    cond do
      # If any probe reached the destination, combine all probes into one DestinationReached
      destinations != [] ->
        all_probes =
          destinations
          |> Enum.reverse()
          |> Enum.flat_map(& &1.probes)

        combined = DestinationReached.new(ttl, all_probes)
        {:ok, :destination_reached, combined}

      # If we got successful probes, create a Hop containing all of them
      probes != [] ->
        hop = Hop.new(ttl, Enum.reverse(probes))
        {:ok, :hop, hop}

      # If all probes timed out, return timeout
      length(timeouts) == opts.probes ->
        {:error, :timeout}

      # If we have errors, return the first one
      errors != [] ->
        {:error, hd(errors)}

      # Fallback to timeout
      true ->
        {:error, :timeout}
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
      IO.write("\r#{ttl}  #{stars}")
    end
  end

  defp print_timeout_final(ttl, stars, opts) do
    if opts.print_output do
      IO.write("\r#{ttl}  #{stars}\n")
    end
  end

  defp do_print(%Hop{} = hop) do
    # Group probes by source address to show different paths
    grouped =
      hop.probes
      |> Enum.group_by(fn probe -> {probe.source_addr, probe.source_domain} end)
      |> Enum.map_join("\n   ", fn {{addr, domain}, probes} ->
        times = probes |> Enum.map(&Probe.time_ms/1) |> Enum.map_join("  ", &"#{&1}ms")
        "#{domain} (#{format_addr(addr)}) #{times}"
      end)

    IO.write("\r#{hop.ttl}  #{grouped}\n")
  end

  defp do_print(%DestinationReached{} = dest) do
    # Group probes by address to show different paths (similar to Hop)
    grouped =
      dest.probes
      |> Enum.group_by(fn probe -> {probe.source_addr, probe.source_domain} end)
      |> Enum.map_join("\n   ", fn {{addr, domain}, probes} ->
        times =
          probes
          |> Enum.map(&Probe.time_ms/1)
          |> Enum.map_join("  ", &"#{&1}ms")

        case domain do
          nil -> "#{format_addr(addr)} #{times}"
          domain -> "#{domain} (#{format_addr(addr)}) #{times}"
        end
      end)

    IO.write("\r#{dest.ttl}  #{grouped}\n")
  end

  defp do_print(%Error{} = error) do
    IO.write("\r#{error.ttl}  #{inspect(error.reason)}\n")
  end

  defp format_addr(addr) when is_tuple(addr), do: :inet.ntoa(addr)
  defp format_addr(addr), do: addr
end
