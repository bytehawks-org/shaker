# Deployment guide

## Containers

### Image

```dockerfile
# --- build stage: Distillery builds into a staged root (no root privileges, no /opt writes)
FROM debian:12 AS build
RUN apt-get update && apt-get install -y build-essential perl python3-yaml git
COPY distillery /opt/bytehawks/core/distillery
RUN python3 /opt/bytehawks/core/distillery/scripts/autobuilder.py build --package nginx --with-deps

# --- runtime stage: any base, Shaker needs only bash
FROM debian:12-slim
COPY --from=build /opt/bytehawks /opt/bytehawks
COPY shaker /opt/bytehawks/core/shaker
ENV PATH=/opt/bytehawks/core/shaker/bin:$PATH
RUN shaker install nginx            # user 1001:0, dirs, group-writable state
USER 1001
EXPOSE 8080
ENTRYPOINT ["shaker", "run", "nginx"]
```

Notes
* `install` at build time stores the state in the image layer and makes it group-0 writable, so any
  uid can update it. With `readOnlyRootFilesystem: true` set `BH_STATE` to an `emptyDir` path: the
  install record is then absent (a `verify` WARN, not a failure), everything else works.
* Add `--init` (docker) / `shareProcessNamespace` or `tini` if the service forks children and does not reap them.
* `shaker install` can run without root in rootless builds: `BH_SHAKER_ALLOW_NONROOT=true`.

### Parameters

```sh
docker run -e BH_NGINX_PORT=9000 -e NGINX_HTTP_PORT_NUMBER=9000 myimage     # env / Bitnami alias
docker run myimage --port=9000 --server-name=example.com                    # CMD arguments: see below
docker run -v ./secrets:/run/secrets:ro -e BH_APP_PASSWORD_FILE=/run/secrets/pw myimage
```
Arguments after the image name are passed to `shaker run nginx` only if the ENTRYPOINT is
`["shaker","run","nginx"]` and the arguments are declared flags of the package (`--port`, ...).
To pass raw arguments to the service use `--`: `... myimage -- -V`.

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: nginx}
spec:
  replicas: 2
  selector: {matchLabels: {app: nginx}}
  template:
    metadata: {labels: {app: nginx}}
    spec:
      securityContext: {runAsNonRoot: true, fsGroup: 0, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: nginx
          image: registry.example.com/nginx:1.28.0
          args: ["--port=8080", "--server-name=example.com"]
          env:
            - {name: BH_NGINX_WORKER_PROCESSES, value: "2"}
            - name: BH_APP_PASSWORD_FILE            # secret parameter of a package that declares it
              value: /run/secrets/app/password
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          volumeMounts:
            - {name: secret, mountPath: /run/secrets/app, readOnly: true}
          readinessProbe: {tcpSocket: {port: 8080}}
          livenessProbe:
            exec: {command: [shaker, verify, nginx, --no-health]}   # drift detection as a probe
            periodSeconds: 300
      volumes:
        - {name: secret, secret: {secretName: app-secret}}
```

### OpenShift / restricted PodSecurity

The platform assigns an arbitrary uid with gid 0. Shaker's model is built for it: directories are
`1001:0` with `g+rwX`, `ensure_passwd_entry` makes the uid resolvable, state is group-writable, the
service never needs root. Do not set `runAsUser`; keep `fsGroup` unset or 0.

## Legacy servers and VMs

### Provision

```sh
sudo git clone https://github.com/bytehawks-org/shaker /opt/bytehawks/core/shaker
sudo /opt/bytehawks/core/shaker/bin/shaker bootstrap          # /opt/bytehawks + /opt/bh
sudo ln -s /opt/bytehawks/core/shaker/bin/shaker /usr/local/bin/shaker
# artifacts built by Distillery are rsynced/unpacked into /opt/bytehawks/<pkg>
sudo shaker install nginx
```

### Configure (files, as usual)

```ini
# /opt/bytehawks/etc/nginx/nginx.ini
[server]
port = 8081
name = example.com
```
Overrides without touching the file: `/opt/bytehawks/etc/nginx/nginx.ini.d/50-local.conf`
(`server.port=8082`) or an environment variable in the unit. Check what wins:
`shaker env nginx --format=explain`.

### systemd

```sh
shaker unit nginx | sudo tee /etc/systemd/system/nginx.service
sudo systemctl daemon-reload && sudo systemctl enable --now nginx
```
The generated unit runs `shaker init` as `ExecStartPre` and `shaker run --no-init` as `ExecStart` under
`User=`/`Group=` of the package, with `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`,
`PrivateTmp`, `ReadWritePaths` limited to the package directories and the state, and the package's stop signal.
Reload after a parameter change: `systemctl restart nginx` (init re-renders).
Audit from monitoring: `shaker verify nginx --strict` (exit code) or a timer.

### Hosts without systemd

```sh
sudo shaker run nginx --daemon      # detached, PID file, log in /opt/bytehawks/var/log/nginx.log
sudo shaker stop nginx
```
For SysV/OpenRC write a 5-line script around these two commands (unit generation is on the roadmap).

### Prerequisites from the distro

```sh
sudo shaker pkg update
sudo shaker pkg install ca-certificates tzdata         # same line on Debian, RHEL, SUSE, Alpine, Arch
```

## Which mode where

| Concern | Container | Legacy VM |
|---|---|---|
| install | image build | provisioning (once) |
| parameters | env, args, `_FILE` | files + drop-ins (+ env) |
| process | ENTRYPOINT, PID 1, `exec` | systemd unit or `--daemon` |
| user | uid from platform, group 0 | declared user, dropped by systemd/`setpriv` |
| state | image + `emptyDir`/volume | `/opt/bytehawks/var/lib/shaker` |
| audit | probe, CI | timer, monitoring |
| upgrade | new image | new artifact + `shaker init` |
