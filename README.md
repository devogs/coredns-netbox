# coredns-netbox

A [CoreDNS](https://coredns.io) Docker image built with the
[NetBox external plugin](https://github.com/oz123/coredns-netbox-plugin).
It answers DNS queries straight from the [NetBox](https://netbox.dev) API, so the IP addresses you
document in NetBox become resolvable names without any zone file to maintain.

- CoreDNS `v1.15.0` + NetBox plugin, built from source (static binary, `linux/amd64`)
- Minimal runtime image (`distroless/static`, non-root)
- Configured with environment variables: only the NetBox URL and token are required

## How it works

The plugin looks up the **`dns_name`** field of the IP addresses in NetBox:

| Query | NetBox lookup | Answer |
|-------|---------------|--------|
| `A fw1.lab.local` | IPv4 address with `dns_name = fw1.lab.local` | A record |
| `AAAA fw1.lab.local` | IPv6 address with `dns_name = fw1.lab.local` | AAAA record |
| `PTR 3.2.1.10.in-addr.arpa` | IP address `10.1.2.3` | `dns_name` of that address |

Names unknown to NetBox are forwarded to an upstream resolver (`1.1.1.1` by default), so the container
can be used as the only DNS server of a host or a lab.

`dns_name` must be the **full name** (e.g. `fw1.lab.local`), exactly as it is queried.

## Quick start

```bash
docker run -d --name coredns-netbox -p 53:53/udp -p 53:53/tcp \
  -e NETBOX_URL="http://netbox.example.com:8080" \
  -e NETBOX_TOKEN="your-api-token" \
  devogs/coredns-netbox:latest

dig @127.0.0.1 fw1.lab.local
```

### Docker Compose

```bash
cp .env.example .env     # set NETBOX_URL and NETBOX_TOKEN
docker compose up -d
```

[docker-compose.yml](docker-compose.yml) reads its settings from `.env` (`env_file`). The same
variables can also be set inline with `environment:`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NETBOX_URL` | *required* | NetBox base URL, **without** `/api` (e.g. `http://netbox:8080`) |
| `NETBOX_TOKEN` | *required* | NetBox API token (read-only is enough) |
| `NETBOX_ZONES` | `.` | Zone answered from NetBox. `.` means every name; use e.g. `lab.local` to restrict it |
| `NETBOX_TTL` | `5m` | TTL of the answers (Go duration: `30s`, `5m`, `1h`) |
| `NETBOX_TIMEOUT` | `5s` | Timeout of the NetBox API calls |
| `DNS_UPSTREAM` | `1.1.1.1` | Resolver for names NetBox does not know (an IP, or `/etc/resolv.conf`) |
| `DNS_CACHE_TTL` | `30` | Cache duration in seconds |

Each variable holds **one value** (one zone, one upstream). For several zones or upstreams, use a custom
Corefile (below).

Compose `env_file` values may be quoted (`NETBOX_URL="http://..."`); with plain `docker run --env-file`
the quotes would be kept, so leave them out there.

### Simple or advanced

- **Simple**: set `NETBOX_URL` and `NETBOX_TOKEN`. Every name is looked up in NetBox first, then forwarded.
- **Zone**: add `NETBOX_ZONES=lab.local` to only ask NetBox for `*.lab.local`. Reverse (`PTR`) lookups
  need the reverse zone as well, which needs a custom Corefile (e.g. `netbox lab.local 1.10.in-addr.arpa`).
- **Custom Corefile**: mount your own file over the default one.

```yaml
    volumes:
      - ./Corefile:/etc/coredns/Corefile:ro
```

The default [Corefile](Corefile) is a good starting point. The `netbox` plugin options are described in the
[plugin documentation](https://github.com/oz123/coredns-netbox-plugin#syntax).

## Notes

- **Port 53 on the host**: if it is already used (e.g. `systemd-resolved`), publish another port such
  as `"5353:53/udp"` and test with `dig -p 5353`.
- **NetBox errors**: if NetBox is unreachable or the token is wrong, the plugin answers `SERVFAIL` instead
  of falling through. Check `docker logs coredns-netbox`.
- **HTTPS**: the system CA store is used. For a private CA, use a custom Corefile with the plugin's
  `tls` option.
- Every query makes one API call to NetBox (the final answer is cached for `DNS_CACHE_TTL` seconds).

## Build it yourself

```bash
docker build -t coredns-netbox .
docker build --build-arg COREDNS_VERSION=v1.15.0 --build-arg NETBOX_PLUGIN_VERSION=81715e2 -t coredns-netbox .
```

CoreDNS has no dynamic plugins, so the image compiles CoreDNS with
`netbox:github.com/oz123/coredns-netbox-plugin` added to `plugin.cfg` (before `file` and `forward`, as the
plugin requires).

## License

[Apache License 2.0](LICENSE), the same license as CoreDNS and the NetBox plugin.
