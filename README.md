# Monitoring Proxy

Docker image to run a proxy container for a monitoring system based on
[Prometheus][prometheus] and tools that produce Prometheus metrics like the
[Prometheus Node Exporter][prometheus-node-exporter]. The proxy allows
Prometheus to reach node exporters running on machines outside its network
boundary without exposing those exporters to the outside world.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Purpose](#purpose)
- [Configuration](#configuration)
  - [SSH Server](#ssh-server)
    - [Host keys](#host-keys)
  - [Reverse Proxy](#reverse-proxy)
  - [Prometheus](#prometheus)
- [Security](#security)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Purpose

In a **classic Prometheus monitoring system**, Prometheus queries a Prometheus
Node Exporter that is outside its network boundary directly, or through a
reverse proxy. This requires exposing the node exporter to the outside world,
potentially exposing a vulnerability:

```
 Monitoring host         Monitored host
┌───────────────┐       ┌────────────────────────────────────────────────┐
│               │       │                                                │
│ ┌──────────┐  │       │ ┌─────────────┐     ┌────────────────────────┐ │
│ │Prometheus├──┼───────┤►│Reverse proxy├────►│Prometheus Node Exporter│ │
│ └──────────┘  │       │ └─────────────┘     └────────────────────────┘ │
│               │       │                                                │
└───────────────┘       └────────────────────────────────────────────────┘
```

The goal of this Docker image is to provide a **proxy container** into which
machines running a node exporter can open a **remote SSH tunnel**, exposing
their local exporter to Prometheus (through the monitoring proxy) without
exposing it to the outside world:

```
 Monitoring host
┌─────────────────────────────────────┐
│                                     │
│ ┌──────────┐      ┌────────────────┐│
│ │Prometheus├─────►│Monitoring Proxy││
│ └──────────┘      └─────┬──────────┘│
│                         │           │
└──────────────────────┐  │  ┌────────┘
                       │  │  │
                       │  │  │ ▲
                       │  │  │ │ Reverse SSH tunnel
                       │  │  │ │
 Monitored host        │  │  │
┌──────────────────────┘  │  └────────┐
│                         │           │
│    ┌────────────────────▼───┐       │
│    │Prometheus Node Exporter│       │
│    └────────────────────────┘       │
│                                     │
└─────────────────────────────────────┘
```

Assuming you have 10 external hosts to monitor using Prometheus, the monitoring
proxy allows you to expose just one thing: the SSH server port of the proxy;
instead of exposing 10 node exporters through 10 reverse proxies.

There are two things running in the monitoring proxy container:

- [`nginx`][nginx], providing the reverse proxy functionality.
- [`OpenSSH`][openssh], an SSH server allowing other hosts to open remote SSH
  tunnels into the container.

## Configuration

When running the monitoring proxy container, you must make sure that port `80`
is reachable by Prometheus, and that port `22` is reachable by the external
hosts running the Prometheus Node Exporter.

### SSH Server

The following environment variables can be set to customize the behavior of the
container:

| Environment variable           | Default value | Description                                                                                             |
| :----------------------------- | :------------ | :------------------------------------------------------------------------------------------------------ |
| `$MONITORING_PROXY_PUBLIC_KEY` | -             | A public key to add to the `monitoring` user's `~/.ssh/authorized_keys` file when the container starts. |

External hosts can use an SSH client to connect to port `22` of the monitoring
proxy container as the `monitoring` user with the corresponding private key.
That user is allowed to open remote tunnels and nothing else.

Here's a sample `ssh` command that could be used, assuming port `22` of the
monitoring proxy is exposed on `monitoring-proxy.example.com`:

```bash
ssh -R 20001:localhost:9100 -N monitoring-proxy.example.com
```

> Here's an equivalent [autossh][autossh] command you can use to keep the tunnel
> alive if the connection is lost:
>
> ```bash
> /usr/bin/autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -R 20001:localhost:9100 -N monitoring-proxy.example.com
> ```

#### Host keys

New host keys will be generated on startup, but this is not suitable for
production since they will change every time the container restarts. You should
generate and use your own key(s), for example at `/etc/ssh/ssh_host_ed25519_key`
and the corresponding `.pub` paths. No new keys will be generated if at least
one is present.

Public host keys will be logged on startup (either the generated ones or the
ones provided by you).

### Reverse Proxy

The reverse proxy is not configured automatically. It is your responsibility to
provide the `/etc/nginx/conf.d/monitoring-proxy.conf` nginx configuration file
with proxied locations, either by extending this image or mounting the file at
runtime. Here's an example:

```
# /etc/nginx/conf.d/monitoring-proxy.conf

location /external-host-1/ {
  proxy_pass http://localhost:20001/;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}

location /external-host-2/ {
  proxy_pass http://localhost:20002/;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

You can also use the `/etc/monitoring/targets` file instead, which is a shortcut
to generate such a configuration. The following example would generate the same
configuration as shown above:

```
localhost:20001 external-host-1
localhost:20002 external-host-2
```

### Prometheus

Here's what your Prometheus scrape configs could look like for these external
hosts, assuming the monitoring proxy is reachable at the `monitoring-proxy`
hostname:

```yml
scrape_configs:
  - job_name: external_host_1_node_metrics
    metrics_path: /external-host-1/metrics
    static_configs:
      - targets:
          - monitoring-proxy:80
        labels:
          external_host: 1
  - job_name: external_host_2_node_metrics
    metrics_path: /external-host-2/metrics
    static_configs:
      - targets:
          - monitoring-proxy:80
        labels:
          external_host: 2
```

## Security

The monitoring proxy has 2 endpoints which have the following security profiles:

- Port `80` has no security whatsoever. It is assumed to be exposed in a trusted
  network and reachable by Prometheus, presumably in the same network boundary.
- Port `22` requires public key authentication and can be safely exposed to the
  outside world provided that the `monitoring` user's private key is kept secure
  (all monitored hosts will use that key to open a remote SSH tunnel to the
  container).

[autossh]: https://linux.die.net/man/1/autossh
[nginx]: https://www.nginx.com
[openssh]: https://www.openssh.com
[prometheus]: https://prometheus.io
[prometheus-node-exporter]: https://github.com/prometheus/node_exporter
[s6-overlay]: https://github.com/just-containers/s6-overlay
