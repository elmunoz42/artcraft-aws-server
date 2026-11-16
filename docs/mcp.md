# MCP for AI agents

This add-on lets an AI agent on another machine use the headless Craft apps on your
server: open and create documents, run editing commands, and export files. It speaks the
Model Context Protocol (MCP) over Streamable HTTP.

It is off by default.

## What it is built from

| Piece | Source | Role |
| --- | --- | --- |
| Craft CLIs (`photocraft-cli`, `vectorcraft-cli`, ...) | Official `storytold/<app>` Linux releases, pinned by SHA-256 in `docker/mcp/apps.lock.json` | The apps, without a window |
| [artcraft-command-bridge](https://github.com/xiewg1987/artcraft-command-bridge) | Community, MIT, pinned commit | One MCP server with 5 tools in front of every CLI, instead of roughly 800 tool schemas |
| [supergateway](https://github.com/supercorp-ai/supergateway) | MIT, pinned version | Turns the bridge's stdio MCP into Streamable HTTP |
| Caddy | Pinned image | Holds the port, checks the bearer token, serves exported files |

The release pins were taken from [devsolux/storytold](https://github.com/devsolux/storytold),
which reviews them against each release's `SHA256SUMS.txt`.

This is separate from the ArtCraft web app and its library. The Craft apps work on files in
a workspace folder. They do not need an ArtCraft account and cannot generate images or video
with AI models.

## Turn it on

With Terraform:

```hcl
enable_mcp                     = true
mcp_allowed_security_group_ids = ["sg-..."]   # the agent host's security group
```

On a host that is already running, edit `.env` and re-run bootstrap:

```bash
# in /opt/artcraft-cloud/.env
MCP_ENABLED=true

sudo scripts/bootstrap.sh
sudo scripts/compose.sh build mcp-bridge
sudo scripts/compose.sh up -d mcp-bridge mcp-proxy
sudo scripts/mcp-smoke-test.sh
```

Bootstrap creates the workspace and generates `MCP_TOKEN` in `.env` if it is empty. The
token is never printed. Read it on the instance when you need to hand it to an agent:

```bash
sudo grep '^MCP_TOKEN=' /opt/artcraft-cloud/.env
```

## Connect an agent

| | |
| --- | --- |
| URL | `http://<instance private IP>:8811/mcp` |
| Transport | Streamable HTTP |
| Header | `Authorization: Bearer <MCP_TOKEN>` |

Store the token as a secret in your agent platform and pass it as an environment variable.
Examples:

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.artcraft]
url = "http://10.0.0.5:8811/mcp"
bearer_token_env_var = "ARTCRAFT_MCP_TOKEN"
```

```bash
# Claude Code
claude mcp add --transport http artcraft http://10.0.0.5:8811/mcp \
  --header "Authorization: Bearer $ARTCRAFT_MCP_TOKEN"
```

Check your client's documentation for the exact keys; they change between versions.

## Tools

| Tool | Use |
| --- | --- |
| `artcraft_apps` | Which apps are installed |
| `artcraft_commands` | List or describe an app's command IDs |
| `artcraft_run` | Run a list of commands in one headless session, with optional input and output files |
| `artcraft_cli` | Run any CLI subcommand directly (convert, info, batch, ...) |
| `artcraft_help` | An app's `--help` text |

A typical loop for an agent: `artcraft_apps`, then `artcraft_commands` for the app it
needs, then `artcraft_run` with an `output` path, asking for a `preview` to check the
result.

## Files

Inside the bridge the workspace is `/work`. On the host it is `${DATA_DIR}/craft-work`.

| Path the agent uses | Purpose |
| --- | --- |
| `/work/inputs/` | Source files: logos, photos, brand assets |
| `/work/outputs/` | Where to save and export |

**Getting results out.** Everything under `outputs/` can be downloaded with the same token:

```bash
curl -H "Authorization: Bearer $ARTCRAFT_MCP_TOKEN" -O http://10.0.0.5:8811/files/banner.png
```

`GET /files/` lists the folder. Small previews (up to 1024 px) also come back inline from
`artcraft_run`.

**Getting source files in.** There is no upload endpoint yet. Put files into
`${DATA_DIR}/craft-work/inputs/` on the instance yourself (they must be readable by uid
10001), or have agents build documents from scratch. The bridge has no internet access, so
it cannot fetch a URL either.

## Choosing apps

`MCP_APPS` in `.env` lists the apps baked into the bridge image. The default is
`photocraft vectorcraft designcraft deckcraft pdfcraft`. All ids in
`docker/mcp/apps.lock.json` are available. Each adds roughly 50 to 300 MB to the image.
After changing it: `sudo scripts/compose.sh build mcp-bridge && sudo scripts/compose.sh up -d mcp-bridge`.

To move to newer app versions, update the entries in `apps.lock.json` from the release's
`SHA256SUMS.txt` and rebuild.

## Security

An MCP client that holds the token can run any subcommand of the installed apps, which
means reading and writing files as the bridge's user. Treat the token like a shell login.

What limits the damage:

- **The bridge has no network route out.** It sits on an internal Docker network: no
  internet, no instance metadata (so no AWS credentials), no path to the database, search
  or storage containers.
- **It sees only the workspace.** Unprivileged user, read-only filesystem, all Linux
  capabilities dropped, memory and process limits. The only writable places are `/work`
  and a small temporary folder.
- **Every request needs the token.** The proxy answers 401 otherwise, including for file
  downloads.
- **The port is not public.** Terraform refuses `0.0.0.0/0` for it and opens it only to the
  security groups or private ranges you list.

What it does not do:

- **No TLS.** The token crosses your private network in plain HTTP. Keep the port inside a
  VPC or a tunnel. Do not open it to the internet; put it behind the Caddy HTTPS add-on
  first if you ever need that.
- **No per-agent identity.** One token, no audit of who did what beyond the proxy's logs.
- **The apps' own file-access limits are not used.** The bridge drives the CLIs directly,
  so the container is the only boundary.
- **One job's memory can crowd the rest.** On a 4 GB instance the main stack already uses
  most of the RAM. Heavy edits will be slow and may hit `MCP_MEM_LIMIT`.

## Check it

```bash
sudo scripts/mcp-smoke-test.sh
sudo scripts/compose.sh logs mcp-bridge mcp-proxy
```

The smoke test confirms that requests without the token are refused, that an MCP session
starts, that the bridge sees the installed apps, and that PhotoCraft can write a file that
is then downloadable.
