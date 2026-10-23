# Rosetta: one parameter, every dialect

A parameter is declared once (in Distillery `packages.yaml`, `runtime.env`) and compiled to
`<prefix>/.bytehawks/rosetta.map`. Shaker reads only that file.

```
env|type|default|flags|aliases|file_key|cli|native_env|description
BH_VALKEY_PORT|port|6379||VALKEY_PORT,REDIS_PORT|server.port|--port|VALKEY_PORT|Listen port
```

| Column | Meaning |
|---|---|
| env | canonical name, `BH_<PACKAGE>_<NAME>` |
| type | `string secret int uint port bool path enum:a,b` |
| flags | `required` |
| aliases | other env names accepted as input (upstream / Bitnami dialects) |
| file_key | key in config files (`section.key` for ini/json/yaml) |
| cli | flag accepted by `shaker exec/env` (`--port=1`, `--port 1`, bare `--flag` for bool) |
| native_env | extra variable exported with the same value, what the application itself reads |

## Precedence

1. CLI flag
2. canonical env (`X` and `X_FILE` together is an error)
3. `X_FILE` (content of the file; one trailing newline stripped)
4. alias env / `alias_FILE`
5. configuration file, then drop-ins `<file>.d/*.conf` (later wins)
6. default

Container/pod: 1-4 and 6. Legacy host: 5 is discovered at `$BH_ETC/<pkg>/<pkg>.{conf,env,ini,yaml,yml,json}`
(or `/etc/bytehawks/<pkg>/`, or `BH_SHAKER_CONFIG`). Files are parsed, never sourced.

## Provenance

`shaker env <pkg> --format=explain` prints variable, winning source and value (secrets masked):

```
BH_VALKEY_PORT   alias:REDIS_PORT   7000
BH_VALKEY_PASS   env-file           ********
```

## Config file formats

| Ext | Parser | Needs |
|---|---|---|
| `.conf .env .cfg` (default) | `KEY=VALUE`, `export`, quotes, comments | nothing |
| `.ini` | `[section]` -> `section.key` | nothing |
| `.json` | flattened `a.b.0` | `jq` or `python3` |
| `.yaml .yml` | flattened | `python3`+PyYAML or `yq` |

Limits: scalar values on a single line; no variable expansion.

## From env back to native configuration

`shaker render app.conf.tmpl /opt/bh/valkey/etc/valkey.conf` replaces `{{ VAR }}` and `{{ VAR:-default }}`;
a missing variable without default is an error.
