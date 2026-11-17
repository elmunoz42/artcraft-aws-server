# artcraft-cloud

Self-host the ArtCraft web app, API and storage as a personal cloud office on one AWS EC2
instance. Files live on an EBS volume. An optional add-on copies backups to S3.

The Docker stack also runs on any Linux host outside AWS.

> **Status: experimental.** This repository wraps
> [artcraft-personal-server](https://github.com/junwonkim07/artcraft-personal-server), an
> unofficial community template that its author also labels experimental. Versions are pinned
> in [`UPSTREAM.lock`](UPSTREAM.lock). Not affiliated with ArtCraft. ArtCraft itself is under
> a personal-use license: read [`LICENSE-NOTICE.md`](LICENSE-NOTICE.md).

## What you get

- **One `terraform apply`** creates the instance, a separate encrypted data volume, a
  security group with no SSH, an IAM role for SSM Session Manager and an Elastic IP.
- **First boot does the rest:** installs Docker, mounts the volume, clones this repo and the
  pinned upstream, generates secrets on the instance, builds and starts the stack.
- **Backups on a timer**, written to the data volume.
- **S3 sync, off by default.** One Terraform variable (`enable_s3_sync`) or one `.env` flag
  (`S3_SYNC_ENABLED`) turns on a sidecar that uploads backups to a private, versioned,
  encrypted bucket using the instance role.
- **Private by default.** Nothing is open to the internet. You reach the app through an SSM
  port forward. Public HTTPS with Caddy is an experimental add-on.

## Before you start

- **ArtCraft is compiled from source.** There are no published images. Upstream asks for
  4 vCPU, 8 GB RAM plus 8 GB swap and 40 GB free disk for the build, and reports about 30
  minutes on that size. Smaller machines need more swap and much more time.
- **Running it needs about 4 GB of RAM.** The container memory limits add up to roughly
  4.3 GB, so a t3.medium with swap is the floor.
- **AI generation, billing and email are not part of this.** See the upstream README for
  what is and is not verified.

## Deploy on AWS

You need Terraform 1.9 or newer, AWS credentials, and this repository pushed somewhere the
instance can clone it from (your fork).

```bash
cd terraform
cp example.tfvars terraform.tfvars   # set region and repo_url
terraform init
terraform apply
```

Follow the first boot (the build takes a long time):

```bash
aws ssm start-session --target <instance_id>
sudo tail -f /var/log/artcraft-cloud-bootstrap.log
```

Then open the app. `terraform output ssm_port_forward_command` prints a command like this;
run it on your computer (it needs the AWS CLI
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html))
and open <http://localhost:4201>:

```bash
aws ssm start-session --target <instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=4201,localPortNumber=4201
```

Create your account on the sign-up page. Accounts belong to your installation.

### Terraform variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `region` | `us-east-1` | AWS region |
| `repo_url` | required | Git URL of your copy of this repo |
| `repo_ref` | `main` | Branch, tag or commit to deploy |
| `instance_type` | `t3.medium` | See [docs/costs.md](docs/costs.md) for build versus run sizing |
| `volume_size_gb` | `60` | Data volume (Docker data, backups, swap) |
| `swap_gb` | `12` | Swap file created at first boot |
| `create_eip` | `true` | Set `false` if your account is at its Elastic IP quota |
| `enable_s3_sync` | `false` | Create the bucket and turn on the sync sidecar |
| `bucket_name` | generated | Bucket name when sync is on |
| `domain_name` | empty | Set to enable public HTTPS (experimental) |
| `allowed_cidrs` | `0.0.0.0/0` | Who may reach 80/443 when `domain_name` is set |
| `basic_auth_user`, `basic_auth_hash` | empty | Sign-in in front of the app; required with `domain_name` |
| `auto_build` | `true` | `false` prepares the host without building |
| `enable_schedule` | `false` | Start and stop the instance on a schedule (default 5pm to 9pm Pacific, weekdays) |
| `enable_mcp` | `false` | MCP endpoint for AI agents, see [docs/mcp.md](docs/mcp.md) |
| `mcp_allowed_security_group_ids`, `mcp_allowed_cidrs` | empty | Who may reach the MCP port (private sources only) |

Outputs: `public_url`, `instance_id`, `public_ip`, `bucket_name`, `data_volume_id`,
`ssm_port_forward_command`, `ssm_shell_command`.

Tear down with `terraform destroy`. That deletes the data volume and, if it is empty, the
bucket; a bucket that still holds backups must be emptied first.

## Run on any Linux host

```bash
git clone https://github.com/YOUR_USER/artcraft-cloud.git /opt/artcraft-cloud
cd /opt/artcraft-cloud
cp .env.example .env          # set DATA_DIR and UPSTREAM_DIR if /data/artcraft does not suit you
sudo scripts/bootstrap.sh --install-docker --swap-gb 8 --build --start
```

Open <http://localhost:4201> on that machine, or tunnel to it:
`ssh -N -L 4201:127.0.0.1:4201 you@server`.

## S3 sync

On AWS, set `enable_s3_sync = true` and apply. Elsewhere, edit `.env`:

```bash
S3_SYNC_ENABLED=true
S3_BUCKET=my-bucket
```

then `sudo scripts/compose.sh up -d`. That is the same as the long form:

```bash
cd docker
docker compose --env-file ../.env -f docker-compose.yml -f docker-compose.s3.yml up -d
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `S3_SYNC_ENABLED` | `false` | Master switch |
| `S3_BUCKET` | | Destination bucket |
| `S3_PREFIX` | `backups` | Key prefix |
| `SYNC_INTERVAL_SECONDS` | `300` | Seconds between runs |
| `SYNC_DELETE` | `false` | Also delete from the bucket what was deleted locally |

**What is synced:** the backups directory, not the live database. Copying MySQL's files
while it runs gives a copy that cannot be restored, so the timer first writes a consistent
backup (database dump plus media, with checksums) and the sidecar uploads that. The bucket
is therefore as fresh as your last backup: daily by default, change `BACKUP_SCHEDULE` in
`.env` or run `sudo scripts/backup.sh` any time. The API pauses while a backup runs.

Check it:

```bash
sudo scripts/compose.sh ps s3-sync                       # health
sudo scripts/compose.sh exec s3-sync sync.sh status      # last successful sync time
sudo scripts/compose.sh logs s3-sync
```

Restore, on the same or a new instance:

```bash
sudo scripts/restore-from-s3.sh --list
sudo scripts/restore-from-s3.sh --apply          # newest backup; asks before overwriting
```

## MCP for AI agents

An optional add-on lets AI agents drive the headless Craft apps (PhotoCraft, VectorCraft,
DesignCraft, DeckCraft, PdfCraft and more) over the Model Context Protocol. It is off by
default, protected by a bearer token, and must only be reachable from a private network.
Set `enable_mcp = true` in Terraform or `MCP_ENABLED=true` in `.env`. See
[docs/mcp.md](docs/mcp.md).

## Everyday commands

```bash
sudo scripts/compose.sh ps
sudo scripts/compose.sh logs -f storyteller-web
sudo scripts/backup.sh
sudo scripts/compose.sh down      # stop; data is kept
```

## Layout

```
docker/       Compose files: base (includes upstream), S3, Caddy and MCP add-ons, their images
terraform/    Root module, first-boot script, modules: instance, storage, s3_sync
scripts/      bootstrap, compose wrapper, backup, restore-from-s3
docs/         architecture, costs, security
```

## Docs

- [Architecture](docs/architecture.md)
- [Costs](docs/costs.md)
- [Security](docs/security.md)
- [MCP for AI agents](docs/mcp.md)

## License

MIT for this repository's own files. ArtCraft and the upstream template's patches are not
MIT. See [`LICENSE-NOTICE.md`](LICENSE-NOTICE.md).
