# Security

## Defaults

- **No inbound ports.** The security group has no ingress rules unless you set
  `domain_name` or turn on the MCP add-on. All app ports bind to 127.0.0.1 on the instance.
- **MCP is private only.** With `enable_mcp`, one port opens to the security groups or
  private ranges you list, never to the internet, and every request needs a bearer token.
  See [mcp.md](mcp.md) for what that token allows.
- **No SSH, no key pairs.** Shell access and port forwarding go through SSM Session Manager,
  authorised by IAM and logged in CloudTrail.
- **IMDSv2 required.** The hop limit is 2 so the sync sidecar can use the instance role.
  That also means any container on the host can obtain the role's credentials, so keep the
  role small: it has SSM access and, when sync is on, one bucket.
- **Encrypted at rest.** Root and data volumes use EBS encryption; the bucket uses SSE-S3.
- **Least privilege for S3.** The instance role may list, read, write and delete objects in
  the backup bucket only. The bucket blocks public access and refuses non-TLS requests.
- **No access keys on disk.** On EC2 the sidecar uses the instance role.
- **Secrets are generated on the instance** by upstream's `generate-secrets.sh`, stored in
  `${UPSTREAM_DIR}/.env` with mode 600, and never pass through Terraform or user data.

## Backups contain everything

A backup holds the full database (accounts, password hashes) and all media. Anyone who can
read the bucket can read it all. Bucket versioning protects against overwrites and
deletions; it is not a substitute for controlling who has access to the AWS account.

The application secrets in `${UPSTREAM_DIR}/.env` are **not** in the backups. To move to a
new instance without the old data volume you restore data from S3 and new secrets are
generated. Sessions are signed with those secrets, so expect everyone to be signed out.
This path has not been tested end to end; keep a private copy of that `.env` if you want
to be sure.

## Public HTTPS (experimental)

Setting `domain_name` opens 80 and 443 and starts Caddy, which obtains a certificate
automatically and proxies to the web app. Know the limits before you use it:

- **Upstream is verified only at `http://localhost:4201`.** Its API runs in development
  mode and rejects other origins. The Caddy config rewrites the `Origin` header to the
  localhost origin the API expects. This has not been tested end to end; expect to debug
  login or media problems, and prefer the SSM tunnel if you only need access for yourself.
- **Sign-in is mandatory.** ArtCraft's own sign-up page is open to anyone who can reach it,
  so Caddy asks for a username and password (`BASIC_AUTH_USER`, `BASIC_AUTH_HASH`) before
  proxying anything. Terraform refuses a `domain_name` without them. Create the hash with
  `docker run --rm -it caddy:2.11.9-alpine caddy hash-password`.
- **The hash travels in user data** when set through Terraform, readable by anyone with
  `ec2:DescribeInstanceAttribute` on the instance. It is a bcrypt hash, not the password;
  use a long random password. To avoid this, leave the Terraform variables empty and edit
  `.env` on the instance instead.
- **Narrow `allowed_cidrs`** to your own addresses where you can. Port 80 must stay
  reachable from the internet for certificate issuance unless you change Caddy to a DNS
  challenge.
- **The web build carries the public origin**, so changing `DOMAIN_NAME` means rebuilding
  the `webapp` image.

## Things to do yourself

- Turn on MFA for the AWS account and avoid long-lived admin access keys.
- Keep Terraform state private: it contains resource IDs and, if set, the sign-in hash.
- Patch the host (`unattended-upgrades` is on by default on Ubuntu) and rebuild when you
  move the upstream pin.
- MinIO Community is no longer maintained upstream. It is reachable only inside the Docker
  network and on localhost here; do not publish its ports.
