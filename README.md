# Minecraft Server Setup

GitHub Actions workflows that provision and manage a Minecraft server on **any server you can SSH into** — a cloud VM (Azure, AWS, GCP, Hetzner, DigitalOcean), a VPS, or a box under your desk. Nothing GitHub-specific is installed on the host: the workflows run on GitHub-hosted runners, rsync this repository to the host, and execute the scripts there over SSH.

The repository is the source of truth: edit the files in `config/`, push, and the server picks up the change.

## Host requirements

| Requirement | Why |
|---|---|
| SSH reachable from the internet, key-based auth | GitHub-hosted runners connect in |
| Debian or Ubuntu | `provision.sh` uses `apt-get` and `openjdk-*-jre-headless` |
| `systemd` | The server runs as `minecraft.service` |
| `sudo` for the deploy user | Installing packages, managing the service |
| `rsync` installed | Repository sync (`apt-get install rsync`) |
| 4 GB RAM minimum | 8 GB for Paper with plugins and a dozen players |
| TCP 25565 open | Players connect |

To use a non-Debian distro, replace the `apt-get` block in `scripts/provision.sh`; everything else is distro-agnostic.

## How it works

```
config/*  --push-->  GitHub-hosted runner  --ssh/rsync-->  your host
                                                             /opt/minecraft
                                                             systemd: minecraft.service
```

| Path | Purpose |
|---|---|
| `config/server.env` | Server software, version, heap size, JVM flags |
| `config/server.properties` | Vanilla server settings |
| `config/ops.json` | Operators (ships with a placeholder — replace it) |
| `config/whitelist.json` | Allowed players (ships with a placeholder — replace it) |
| `config/banned-players.json` | Ban list |
| `scripts/` | The logic the workflows run on the host; runnable by hand there too |
| `.github/actions/ssh-setup` | Writes the deploy key and rsyncs the repo to the host |

Workflows:

| Workflow | Trigger | Does |
|---|---|---|
| `provision.yml` | Manual | Installs Java, service user, jar, systemd unit. Idempotent, never deletes a world. |
| `deploy.yml` | Push to `config/`/`scripts/`, or manual | Backs up, updates jar, syncs config, restarts, verifies. |
| `backup.yml` | Daily 04:00 UTC, or manual | Consistent world backup with save-off/flush/save-on; optional download as artifact. |

## Setup

1. **Create a deploy key pair** on your machine and put the public half on the host:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/mc_deploy -C github-actions
   ssh-copy-id -i ~/.ssh/mc_deploy.pub <user>@<host>
   ```

   The private half becomes a repository secret. Keep it out of git.

2. **Open the ports.** 25565 for players, 22 for the workflows — in your provider's firewall *and* in `ufw` if the host runs it.

   <details>
   <summary>Azure example</summary>

   ```bash
   az group create -n minecraft-rg -l eastus
   az vm create -g minecraft-rg -n minecraft-vm \
     --image Ubuntu2404 --size Standard_B2ms \
     --admin-username azureuser --ssh-key-values ~/.ssh/mc_deploy.pub \
     --public-ip-sku Standard --storage-sku Premium_LRS
   az vm open-port -g minecraft-rg -n minecraft-vm --port 25565 --priority 1001

   # A dynamic public IP changes on deallocate; pin it and get a DNS name.
   az network public-ip update -g minecraft-rg -n minecraft-vmPublicIP \
     --allocation-method Static --dns-name my-minecraft
   ```
   </details>

   Whatever the provider, give the host a static IP or a DNS name — otherwise a reboot silently breaks both the secret and your players' server entry.

3. **Allow the deploy user to run the scripts as root.** On the host, with `<user>` replaced by your SSH user:

   ```bash
   sudo tee /etc/sudoers.d/minecraft-deploy >/dev/null <<'EOF'
   <user> ALL=(ALL) NOPASSWD: /home/<user>/minecraft-deploy/scripts/provision.sh, \
                              /home/<user>/minecraft-deploy/scripts/update.sh, \
                              /home/<user>/minecraft-deploy/scripts/sync-config.sh, \
                              /home/<user>/minecraft-deploy/scripts/backup.sh, \
                              /home/<user>/minecraft-deploy/scripts/status.sh, \
                              /usr/bin/systemctl restart minecraft, \
                              /usr/bin/cp, /usr/bin/chown
   EOF
   sudo chmod 440 /etc/sudoers.d/minecraft-deploy
   ```

   Read the security note at the bottom before deciding on this.

4. **Add the repository secrets** (*Settings → Secrets and variables → Actions*). The workflows reference an environment named `minecraft`, so add them there if you want an approval gate on deploys; otherwise repository-level secrets work as-is.

   | Secret | Value |
   |---|---|
   | `SSH_HOST` | IP or DNS name of the host |
   | `SSH_USER` | SSH user (e.g. `azureuser`, `ubuntu`, `root`) |
   | `SSH_PRIVATE_KEY` | Contents of `~/.ssh/mc_deploy` |
   | `SSH_KNOWN_HOSTS` | Output of `ssh-keyscan -H <host>` — optional but recommended |

   Optional repository **variable** `SSH_PORT` if sshd is not on 22.

5. **Edit `config/`** — at minimum replace the placeholder UUIDs in `ops.json` and `whitelist.json` with real ones (get a UUID from `https://api.mojang.com/users/profiles/minecraft/<name>`), or set them to `[]`. The sync script refuses to push the placeholder.

6. **Run the *Provision Server* workflow** from the Actions tab.

## Day-to-day

- **Change a setting or add a player:** edit the file in `config/`, commit to `main`. `deploy.yml` backs up, applies, restarts.
- **Upgrade the version:** change `MC_VERSION` (or `MC_TYPE`) in `config/server.env` and push. Set it to `latest` to always track the newest release. The previous jar stays in `/opt/minecraft/jars/`, so rolling back is a one-line revert.
- **Restart only:** run *Deploy Config & Version* manually with `restart-only`.
- **Restore a backup**, on the host:

  ```bash
  sudo systemctl stop minecraft
  sudo -u minecraft tar -xzf /opt/minecraft/backups/world-<stamp>.tar.gz -C /opt/minecraft
  sudo systemctl start minecraft
  ```

- **Console access**, on the host — the server's stdin is a FIFO:

  ```bash
  echo "say hello" | sudo -u minecraft tee /opt/minecraft/console.in
  sudo journalctl -u minecraft -f
  ```

## Notes

- Scheduled workflows do not run while a repository is inactive for 60 days, and they only run on the default branch.
- `backup.yml` keeps the newest 7 archives on the host (`MC_BACKUP_KEEP`). Downloading to a GitHub artifact is opt-in because worlds outgrow artifact limits quickly — for anything serious, push the archive to object storage from the host instead.

## Security

Port 22 is reachable from the whole internet in this setup, because GitHub-hosted runners have no fixed egress IPs to allow-list. Keep `PasswordAuthentication no` in `/etc/ssh/sshd_config` and consider fail2ban.

Anyone who can push to `main` or dispatch a workflow can run the scripts under `sudo` on the host. The sudoers rule in step 3 is scoped to specific scripts rather than blanket `NOPASSWD: ALL`, but those scripts come from the repository — so push access to `main` is still effectively root on the host. Keep the repository private, protect `main`, and never let workflows in this repository run on pull requests from forks.
