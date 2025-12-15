# Traceroute

A (partial) Traceroute re-implementation in Elixir.

Simply start the project with `iex -S mix` and run a trace:

```bash
iex> Traceroute.run("google.com", protocol: :udp, ip_protocol: :ipv4, probes: 3)
1  --redacted-- (--redacted--) 11.235ms  6.939ms  9.518ms
2  192.0.0.1 (192.0.0.1) 11.847ms  12.264ms  13.771ms
3  --redacted-- (--redacted--) 12.738ms  12.677ms  13.035ms
4  fra1901aihb001.versatel.de (62.214.42.58) 14.249ms  16.758ms
   89.246.109.249 (89.246.109.249) 21.941ms
5  72.14.217.70 (72.14.217.70) 21.549ms  20.049ms
6  192.178.109.235 (192.178.109.235) 46.902ms  18.17ms  30.988ms
7  142.250.225.76 (142.250.225.76) 98.751ms
   142.251.64.184 (142.251.64.184) 107.648ms
   142.251.241.75 (142.251.241.75) 18.124ms
8  lcfraa-bt-in-f14.1e100.net (142.251.140.174) 16.132ms  16.391ms
```

For comparison, here's the output from `traceroute`:

```bash
$ traceroute -P udp -w 1 google.com
traceroute to google.com (142.251.140.174), 64 hops max, 40 byte packets
 1  --redacted-- (--redacted--)  3.647 ms  3.184 ms  2.751 ms
 2  192.0.0.1 (192.0.0.1)  8.222 ms  8.685 ms  8.126 ms
 3  --redacted-- (--redacted--)  10.286 ms  9.180 ms  8.877 ms
 4  fra1901aihb001.versatel.de (62.214.42.58)  14.209 ms
    89.246.109.249 (89.246.109.249)  15.354 ms  15.556 ms
 5  72.14.217.70 (72.14.217.70)  16.226 ms *  18.405 ms
 6  192.178.109.153 (192.178.109.153)  17.366 ms *
    192.178.109.235 (192.178.109.235)  19.176 ms
 7  142.251.241.75 (142.251.241.75)  17.459 ms  16.791 ms
    142.251.241.77 (142.251.241.77)  15.151 ms
 8  142.251.241.75 (142.251.241.75)  15.695 ms  16.032 ms  18.588 ms
 9  lcfraa-bt-in-f14.1e100.net (142.251.140.174)  14.811 ms
    108.170.236.249 (108.170.236.249)  17.687 ms *
```

## Features

- Sends probes as `ICMP`, `UDP`, and `TCP` packets
- Supports `IPv4` and `IPv6` (use `ip_protocol: :ipv6`)
- Sends multiple probes in parallel with request staggering
- Automatically resolves hostnames for each hop's IP address
- Returns *all* the data in a structured format

## Configurable Options
- `protocol` - Choose between `:icmp`, `:udp`, or `:tcp` (default: `:udp`)
- `ip_protocol` - Choose between `:ipv4` or `:ipv6` (default: `:ipv4`)
- `max_hops` - Maximum number of hops before aborting (default: `20`)
- `max_retries` - Retry count per hop before moving on (default: `3`)
- `timeout` - Response timeout in seconds (default: `1`)
- `probes` - Number of parallel probes per TTL (default: `3`)
- `print_output` - Toggle console output (default: `true`)

## Caveats and Considerations

- This library is untested on Windows. Please report any issues for investigation.
- You may need to run as `sudo` depending on your OS, though try without it first. IPv6 ICMP probes on macOS definitely require sudo. If you get `:eperm` errors, use `sudo`.
- Running many parallel probes can cause performance issues since each ICMP socket receives (but filters) all ICMP replies. Contact me if this affects you. I have a potential fix which is not yet implemented.

## Testing `IPv6` using WireGuard

Not every routers have IPv6-support, so if you run a traceroute with `ip_protocol: :ipv6` and receive the `{:error, :ehostunreach}` error, try the following:

1. Install `wireguard` (e.g. `brew install wireguard-tools`)
1. Sign up for an `IPv6 Tunnel` (e.g. `route64.org`)
1. Create a `Tunnelbroker` by going to: 
    1. `IPv6 Tunnelbroker`
    1. `Add Tunnelbroker` (under `List tunnelbrokers`)
    1. Select a region close to you. Select `Wireguard`.
    1. Add your home IP (as shown on e.g. [ip.me](ip.me)) into `Remote Endpoint`
    1. Click `Create Tunnelbroker`
1. Navigate back to `List Tunnelbroker` and click on the `Example Config` action button next to your newly created tunnelbroker.
1. Copy the config (starting with `[Interface]`) to a local `w0.conf` file.
1. Enable WireGuard through `wg-quick up w0.conf`
1. Now, you should be able to run traceroutes through IPv6!
1. To disable WireGuard again, run `wg-quick down w0.conf`

## Useful `traceroute` commands to run comparisons

### IPv4

```bash
# Use 1s timeout and the ICMP protocol
traceroute -w 1 -P ICMP fly.io
# Use 1s timeout and the UDP protocol
traceroute -w 1 -P UDP fly.io
# Use 1s timeout and the TCP protocol
# First try without `sudo` but you most likely need elevated permissions
sudo traceroute -w 1 -P tcp google.com
```

### IPv6
```bash
# Use 1s timout and the ICMP protocol
traceroute6 -I -w 1 google.com
# Use 1s timeout and the UDP protocol
traceroute6 -U -w 1 google.com
# Use 1s timeout and the TCP protocol (might need sudo permissions)
traceroute6 -T -w 1 google.com
```

# TODOs

* [ ] De-duplicate ICMP sockets