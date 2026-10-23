# Security

Shaker runs early, often as root, on inputs that operators and pipelines control. The design assumes
inputs may be wrong, sloppy or hostile and fails closed.

## Guarantees

| Area | Guarantee | Mechanism |
|---|---|---|
| Code execution from data | configuration files, `rosetta.map`, `runtime.spec`, `manifest.env`, templates and state are **never sourced or evaluated** | explicit parsers; `${VAR}` / `{{ VAR }}` expanders without `eval`; values containing `$(id)`, backticks or `&` are inserted verbatim (tested) |
| Argument handling | the service command is an argv array, never a shell string; no re-splitting, no globbing | `run\|argv0\|argv1...`, `"${LC_ARGV[@]}"` |
| Secrets in output | never printed | `explain`/debug mask `secret` types and secret-looking names; state stores only a SHA-256 over all parameters |
| Secrets in the environment | provided as files (`*_FILE`) so they stay out of `docker inspect` / `/proc/<pid>/environ` of other processes | Rosetta `_FILE`; `X` + `X_FILE` is an error |
| Framework leakage | the service never sees `BH_SHAKER_*` | `cleanup_bh_shaker_env_vars` before `exec` |
| Privileges | root only where needed (`install`, `init` before the drop); service runs as the declared non-root user or the platform uid | `exec_as_user`; `NoNewPrivileges` in the unit |
| Atomicity | rendered files and state are replaced by rename; a crash never leaves a half-written config | temp file + `mv` in the same directory |
| Drift | manual changes to generated files are detected | SHA-256 recorded at render time, compared by `verify` |
| Audit | what was installed/initialized/run/verified, when, from which recipe | `events.log`, state, recipe hash from Distillery |
| Supply chain (via Distillery) | sources are pinned by SHA-256; an unpinned source refuses to build; the hash is verified **before** any build command runs | see Distillery `docs/SECURITY.md` |

## Threat model

In scope: mis-typed or malicious parameters (env, CLI, config file, drop-ins); malicious *content* of a
config file; a secret leaking through logs or process listings; a writable template/hook directory;
a service started with more privileges than declared.

Out of scope / user responsibility:
* **Hooks are code.** `pre_init/first_init/post_init` scripts run with the privileges of `init`
  (often root). Keep hook directories root-owned and not writable by the service user (`install` creates
  them; do not give them `g+w` unless you accept that the service group can run code as root at the next start).
* **Templates and the bundle are trusted** like the binaries next to them: protect `/opt/bytehawks/*/.bytehawks`
  the same way as `/opt/bytehawks/*/bin`.
* The host package manager and its repositories (`shaker pkg`).
* Container runtime isolation, network policy, image signing.
* A compromised root user.

## Hardening checklist

* Run containers with `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`.
* Pass secrets as mounted files; set only `*_FILE` in the environment.
* Keep `/opt/bytehawks/etc/<pkg>` `0750 root:<group>` when configs hold secrets.
* Use the generated systemd unit (it limits writes to the package directories and the state).
* Run `shaker verify --strict` periodically; alert on drift.
* Keep `BH_SHAKER_HOOKS_CONTINUE` off.

## Known limitations

* A parameter value containing a newline is not supported in config files (single-line values).
* `render_template` does not escape for the target format: a value with a newline can inject a line
  into the rendered config. Validate with a `type` (`port`, `enum`, `path` rejects newlines) rather than `string` when it matters.
* `events.log` is not rotated and is append-only by convention, not enforced (use `chattr +a` or ship it off-host if needed).
* Passwords given on the command line are visible in `ps`; prefer `_FILE`.
* No signature verification of the bundle itself (planned).

## Reporting

Open a private security advisory on the GitHub repository.
