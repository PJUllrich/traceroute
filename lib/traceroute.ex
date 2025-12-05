defmodule Traceroute do
  @moduledoc """
  Performs a traceroute request to a given domain.
  """

  require Logger

  alias Traceroute.Ping
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
    * `{:ok, trace}` if destination is reached.
    * `{:error, :max_hops_exceeded, trace}` if max hops are exceeded.
  """
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
      {:ok, %{time: time, header: %{source_addr: source_addr}} = response}
      when source_addr == ip ->
        print(:response, ttl, response, opts)
        trace = [{ttl, time, response} | trace]
        {:ok, trace}

      {:ok, %{status: :reached, time: time} = response} ->
        print(:response, ttl, response, opts)
        trace = [{ttl, time, response} | trace]
        {:ok, trace}

      {:ok, response} ->
        print(:response, ttl, response, opts)
        trace = [{ttl, response.time, response} | trace]
        do_run(ip, ttl + 1, max_hops - 1, 0, trace, opts)

      {:error, :timeout} ->
        stars = "*" |> List.duplicate(min(retries + 1, opts.max_retries)) |> Enum.join(" ")

        if retries < opts.max_retries do
          print(:timeout, ttl, stars, opts)
          do_run(ip, ttl, max_hops, retries + 1, trace, opts)
        else
          print(:timeout, ttl, stars <> "\n", opts)
          do_run(ip, ttl + 1, max_hops - 1, 0, [{ttl, :timeout} | trace], opts)
        end

      {:error, error} ->
        print(:error, ttl, error, opts)
        trace = [{ttl, error} | trace]
        do_run(ip, ttl + 1, max_hops - 1, 0, trace, opts)
    end
  end

  defp print(type, ttl, data, opts) do
    if Map.fetch!(opts, :print_output) do
      do_print(type, ttl, data)
    end
  end

  defp do_print(:response, ttl, %{
         time: time,
         header: %{source_domain: source_domain, source_addr: source_addr}
       }) do
    request_time = Float.round(time / 1000, 3)
    IO.write("\r#{ttl} #{source_domain} (#{:inet.ntoa(source_addr)}) #{request_time}ms\n")
  end

  defp do_print(:response, ttl, %{time: time}) do
    request_time = Float.round(time / 1000, 3)
    IO.write("\r#{ttl} reached destination #{request_time}ms\n")
  end

  defp do_print(:timeout, ttl, error) do
    IO.write("\r#{ttl} #{error}")
  end

  defp do_print(:error, ttl, error) do
    IO.write("\r#{ttl} #{error}\n")
  end
end
