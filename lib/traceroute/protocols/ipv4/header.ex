defmodule Traceroute.Protocols.IPv4.Header do
  @moduledoc """
  Represents an IPv4 header.

  See: https://en.wikipedia.org/wiki/IPv4#Header
  """
  defstruct [
    :ihl_version,
    :ihl,
    :tos,
    :total_length,
    :identification,
    :flags,
    :offset,
    :ttl,
    :protocol,
    :header_checksum,
    :source_domain,
    :source_addr,
    :destination_addr,
    :options
  ]
end
