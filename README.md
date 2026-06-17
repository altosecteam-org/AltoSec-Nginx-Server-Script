# AltoSec Nginx Server Script

Node bootstrap scripts for the [Altosec LoadBalancer](https://github.com/altosecteam-org/Altosec-nginx-manager).

## Provision a node as a CI runner

Turns a fresh Debian/Ubuntu box into a GitHub Actions **self-hosted runner** for
the LoadBalancer repo: installs Docker (to build + deploy the image), downloads and
registers the runner, and runs it as a systemd service (starts on boot,
auto-restarts). The runner host doubles as the deployment host.

Get a registration token from the LoadBalancer repo →
**Settings → Actions → Runners → New self-hosted runner** (valid ~1 hour), then on
the node:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/altosecteam-org/AltoSec-Nginx-Server-Script/main/linux/bootstrap-node.sh \
  | sudo bash -s -- --token <registration-token> --runner-name proxy-node-01
```

| Flag | Required | Default | Meaning |
|---|---|---|---|
| `--token` | ✅ | — | GitHub runner registration token |
| `--runner-name` | ✅ | — | Name to register the runner under |
| `--url` | | the LoadBalancer repo | Repo the runner registers against |
| `--labels` | | — | Extra runner labels (comma-separated) |
| `--user` | | `gha-runner` | Local user that runs the runner |
| `--version` | | latest | Pin a specific runner version |

Re-runnable: re-registers the same name with `--replace`.

> **Firewall:** the script always opens TCP 80/443/8765 on the host firewall (ufw
> or firewalld) if one is active — this is not optional. **Cloud security groups
> are outside the OS** — if a VM still refuses external connections, open those
> ports in your cloud provider's console (AWS/GCP/Azure/etc.).

### From Windows

```powershell
./windows/Install-Runner.ps1 -RunnerHost 203.0.113.10 -RunnerName proxy-node-01 -Token <token>
```

Runs the same one-liner on the target over SSH (needs the OpenSSH client).
