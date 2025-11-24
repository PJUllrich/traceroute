# Traceroute

A (partial) Traceroute re-implementation in Elixir.

Simply start the project with `iex -S mix` and run a trace:

```elixir
Traceroute.run("fly.io")
```

## `traceroute` commands

```bash
# Use 1s timeout and the UDP protocol
traceroute -w 1 -P UDP fly.io
# Use 1s timeout and the ICMP protocol
traceroute -w 1 -P ICMP fly.io
```

## Comparisons

### Tracing `fly.io` through ICMP:

```bash
# Output of "traceroute -w 1 -P ICMP fly.io
$ traceroute -w 1 -P ICMP fly.io
traceroute to fly.io (37.16.18.81), 64 hops max, 48 byte packets
    1  192.168.0.1 (192.168.0.1)  0.880 ms  0.519 ms  0.387 ms
    2  --redacted-- (--redacted--)  1.417 ms  1.249 ms  1.165 ms
    3  --redacted-- (--redacted--)  2.778 ms  3.787 ms  2.270 ms
    4  * * *
    5  * * *
    6  * * *
    7  nl-ams14a-ri1-ae-8-0.aorta.net (84.116.135.38)  4.702 ms  4.157 ms  4.039 ms
    8  * * *
    9  ae7.cr4-ams1.ip4.gtt.net (213.200.117.170)  5.396 ms  6.107 ms  5.824 ms
    10  ip4.gtt.net (46.33.82.122)  4.452 ms  4.556 ms  4.473 ms
    11  * * *
    12  ip-37-16-18-81.customer.flyio.net (37.16.18.81)  4.641 ms  4.447 ms  4.311 ms

# Output of Traceroute.run/2
iex(1)> Traceroute.run("fly.io", protocol: :icmp)
    1 192.168.0.1 (192.168.0.1) 0.733ms
    2 --redacted-- (--redacted--) 1.232ms
    3 --redacted-- (--redacted--) 3.76ms
    4 * * *
    5 * * *
    6 * * *
    7 nl-ams14a-ri1-ae-8-0.aorta.net (84.116.135.38) 4.452ms
    8 * * *
    9 ae7.cr4-ams1.ip4.gtt.net (213.200.117.170) 6.12ms
    10 ip4.gtt.net (46.33.82.122) 5.006ms
    11 * * *
    12 ip-37-16-18-81.customer.flyio.net (37.16.18.81) 4.913ms
```

### Tracing `google.com` through UDP

```bash
# Output of "traceroute -w 1 -P UDP google.com"
$ traceroute -w 1 -P UDP google.com
traceroute to google.com (142.250.179.142), 64 hops max, 40 byte packets
  1  192.168.0.1 (192.168.0.1)  1.362 ms  0.924 ms  0.875 ms
  2  --redacted-- (--redacted--)  1.771 ms  1.507 ms  1.664 ms
  3  --redacted-- (--redacted--)  3.499 ms  3.008 ms  2.879 ms
  4  * * *
  5  * * *
  6  74.125.243.79 (74.125.243.79)  5.702 ms
    74.125.242.163 (74.125.242.163)  6.283 ms
  7  142.250.211.91 (142.250.211.91)  5.032 ms
  8  ams17s10-in-f14.1e100.net (142.250.179.142)  4.491 ms  4.565 ms  4.454 ms

# Output of Traceroute.run/2
iex(1)> Traceroute.run("google.com", protocol: :udp)
  1 192.168.0.1 (192.168.0.1) 1.386ms
  2 --redacted-- (--redacted--) 2.169ms
  3 --redacted-- (--redacted--) 3.935ms
  4 * * *
  5 * * *
  6 74.125.242.163 (74.125.242.163) 6.438ms
  7 142.250.211.91 (142.250.211.91) 4.994ms
  8 ams17s10-in-f14.1e100.net (142.250.179.142) 4.818ms
```

# TODOs

* [ ] Handle interweaved ICMP responses. Refactor ICMP response handlers to register themselves in a Registry and send the ICMP message their way based on the reply identifier.
* [ ] Add TCP tracing