# shaker

A modular bash framework for hardened initialization and identity governance across container
and legacy VM environments. It is the runtime/installation counterpart of
[Distillery](https://github.com/bytehawks-org/distillery): Distillery declares and builds,
Shaker normalizes and applies.

* Distro-agnostic (apt, dnf, yum, microdnf, tdnf, zypper, apk, pacman), systemd optional.
* Rosetta: CLI flags, env, upstream aliases, `*_FILE` secrets and config files -> one canonical ENV.
* Layout: `/opt/bytehawks` (`/opt/bh`), code in `/opt/bytehawks/core/shaker`.

```sh
shaker detect
shaker exec valkey --port=7000 -- /opt/bh/valkey/bin/valkey-server
shaker env valkey --format=explain
./tests/run.sh
```

Docs: [architecture](docs/ARCHITECTURE.md), [Rosetta](docs/ROSETTA.md).
