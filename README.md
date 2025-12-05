# Traceroute

A (partial) Traceroute re-implementation in Elixir.

Simply start the project with `iex -S mix` and run a trace:

```elixir
Traceroute.run("fly.io")
```

## `traceroute` commands

```bash
# Use 1s timeout and the ICMP protocol
traceroute -w 1 -P ICMP fly.io
# Use 1s timeout and the UDP protocol
traceroute -w 1 -P UDP fly.io
# Use 1s timeout and the TCP protocol
# First try without `sudo` but you most likely need elevated permissions
sudo traceroute -w 1 -P tcp google.com
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

### Tracing `peterullrich.com` through TCP

```bash
# Output of "
➜  traceroute git:(main) ✗ sudo traceroute -w 1 -P tcp peterullrich.com
traceroute to peterullrich.com (67.205.137.221), 64 hops max, 40 byte packets
 1  192.168.0.1 (192.168.0.1)  3.360 ms  2.787 ms  3.503 ms
 2  --redacted-- (--redacted--)  3.873 ms  3.847 ms  3.473 ms
 3  --redacted-- (--redacted--)  5.613 ms  5.436 ms  4.975 ms
 4  * * *
 5  * * *
 6  ae-6.r23.amstnl07.nl.bb.gin.ntt.net (129.250.2.232)  13.904 ms  16.534 ms  9.488 ms
 7  ae-0.r22.londen12.uk.bb.gin.ntt.net (129.250.5.151)  12.893 ms
    ae-2.r22.parsfr04.fr.bb.gin.ntt.net (129.250.2.3)  19.339 ms
    ae-0.r22.londen12.uk.bb.gin.ntt.net (129.250.5.151)  14.310 ms
 8  ae-14.r23.nwrknj03.us.bb.gin.ntt.net (129.250.4.194)  91.435 ms  88.211 ms  87.520 ms
 9  ae-8.a03.nycmny17.us.bb.gin.ntt.net (129.250.3.153)  90.290 ms
    ae-1.a01.nwrknj03.us.bb.gin.ntt.net (129.250.3.25)  92.959 ms
    ae-14.a00.nwrknj03.us.bb.gin.ntt.net (129.250.3.177)  97.526 ms
10  ae-0.digital-ocean.nycmny17.us.bb.gin.ntt.net (157.238.179.70)  90.229 ms
    ae-0.digital-ocean.nwrknj03.us.bb.gin.ntt.net (157.238.227.61)  89.552 ms  96.310 ms
11  * * *
12  * * *
13  * * *
14  * * *
15  * * *
# Max hops exceeded. Never reaches destination

# Output of Traceroute.run/2
iex(1)> Traceroute.run("peterullrich.com", protocol: :tcp)
1 192.168.0.1 (192.168.0.1) 3.827ms
2 --redacted-- (--redacted--) 19.156ms
3 --redacted-- (--redacted--) 9.667ms
4 * * *
5 192.168.0.1 (192.168.0.1) 1000.543ms # TTL 5 bounces back to the modem?
6 ae-6.r23.amstnl07.nl.bb.gin.ntt.net (129.250.2.232) 9.416ms
7 ae-0.r22.londen12.uk.bb.gin.ntt.net (129.250.5.151) 27.946ms
8 ae-14.r23.nwrknj03.us.bb.gin.ntt.net (129.250.4.194) 93.081ms
9 ae-14.a02.nycmny17.us.bb.gin.ntt.net (129.250.3.51) 92.098ms
10 ae-1.digital-ocean.nwrknj03.us.bb.gin.ntt.net (157.238.227.81) 89.091ms
11 * * *
12 ae-6.r23.amstnl07.nl.bb.gin.ntt.net (129.250.2.232) 1000.395ms
13 ae-1.a01.nwrknj03.us.bb.gin.ntt.net (129.250.3.25) 1001.011ms
14 * * *
15 * * *
16 * * *
17 reached destination 96.644ms
```

# TODOs

* [x] Add TCP tracing
* [x] Allow disabling of output
* [x] Handle UDP connection responses
* [x] Handle interweaved ICMP responses.
* [x] Send multiple probes for every hop
* [ ] Support IPv6