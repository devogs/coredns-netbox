# syntax=docker/dockerfile:1

ARG GO_VERSION=1.26
ARG COREDNS_VERSION=v1.15.0
ARG NETBOX_PLUGIN_VERSION=latest

# --- Build stage: CoreDNS compiled with the NetBox external plugin ---
FROM golang:${GO_VERSION} AS build
ARG COREDNS_VERSION
ARG NETBOX_PLUGIN_VERSION

RUN git clone --depth 1 --branch ${COREDNS_VERSION} https://github.com/coredns/coredns /coredns
WORKDIR /coredns

# External plugins are enabled in plugin.cfg; "netbox" must run before "file" and "forward".
RUN sed -i 's|^file:file|netbox:github.com/oz123/coredns-netbox-plugin\nfile:file|' plugin.cfg \
 && go get github.com/oz123/coredns-netbox-plugin@${NETBOX_PLUGIN_VERSION} \
 && go generate \
 && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/coredns .

# --- Runtime stage ---
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/coredns /coredns
COPY Corefile /etc/coredns/Corefile

# Defaults so that only NETBOX_URL and NETBOX_TOKEN are mandatory.
ENV NETBOX_ZONES="." \
    NETBOX_TTL="5m" \
    NETBOX_TIMEOUT="5s" \
    DNS_UPSTREAM="1.1.1.1" \
    DNS_CACHE_TTL="30"

EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/coredns"]
CMD ["-conf", "/etc/coredns/Corefile"]
