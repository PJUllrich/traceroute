## [0.2.2] - 2026-01-09

- Fix IPv6 protocol selection on Linux. It had `:"IPV6-ICMP"` hard-coded, but that's macOS only.

## [0.2.1] - 2025-12-31

- Fix a race condition in `ICMPConn` where the connection could terminate prematurely. This occurred when the last registered process terminated while another process was in the middle of registering (between calling `ICMPConn.get_or_start_conn/1` and `ICMPConn.register/4`).

## [0.2.0] - 2025-12-31

- Completely rewrite how ICMP packets are received. 
    - Previously, every probe would start its own ICMP socket and ignore packets that were meant for other ICMP sockets based on the identifier of the received packet. However, not all ICMP sockets received all packets, so Traceroute would return many more `TimeExceeded` responses than it should. Now, we start only a single ICMP socket (one for `IPv4` and one for `IPv6`) upon request and receive and send all packets through that singleton socket.
- Fix `DestinationReached` probe count. 
    - We previously ignored probes that did not receive a "destination reached" response but had the same TTL as probes that did. We now include such probes in the response because although they didn't receive the correct ICMP response, they most likely still reached the destination.

## [0.1.2] - 2025-12-31

- Add `min_ttl` option to start the traceroute at a higher time-to-live than `1`, which makes it easier to skip the first hops (e.g. your local router)
- Return `Probe.source_domain` as string instead of charlist.

## [0.1.1] - 2025-12-15

- Return `{:error, :nxdoamain}` if domain cannot be parsed into an IP
- If an IP-tuple is provided, auto-select the correct `ip_protocol: :ipv4|:ipv6`
- Add instructions for setting up an IPv6 tunnel

## [0.1.0] - 2025-12-06

- Initial release