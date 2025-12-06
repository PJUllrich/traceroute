defmodule Traceroute.Protocols.IPv6.Header do
  @doc """
  Represents an IPv6 header.

  See: https://en.wikipedia.org/wiki/IPv6_packet#Fixed_header
  """

  defstruct [
    :version,
    :ds,
    :ecn,
    :flow_label,
    :payload_length,
    :next_header,
    :max_hops,
    :source_addr,
    :source_domain,
    :destination_addr
  ]
end
