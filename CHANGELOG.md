## [0.1.2] - 2025-12-15

- Add `min_ttl` option to start the traceroute at a higher time-to-live than `1`, which makes it easier to skip the first hops (e.g. your local router)
- Return `Probe.source_domain` as string instead of charlist.

## [0.1.1] - 2025-12-15

- Return `{:error, :nxdoamain}` if domain cannot be parsed into an IP
- If an IP-tuple is provided, auto-select the correct `ip_protocol: :ipv4|:ipv6`
- Add instructions for setting up an IPv6 tunnel

## [0.1.0] - 2025-12-06

- Initial release