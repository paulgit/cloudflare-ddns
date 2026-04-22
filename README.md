# Cloudflare Dynamic DNS &nbsp;![Version](https://img.shields.io/badge/version-2.1-blue)

## Introduction

If you run a server from your home network, or want to access your home
computer remotely, one challenge is tracking your public IP address, as most
domestic internet connections use a dynamic IP that changes periodically. A
Dynamic DNS (DDNS) service solves this by keeping a DNS record up to date
automatically.

This script uses the Cloudflare API (v4) to act as a DDNS client. It detects
your current public IP address and updates a Cloudflare DNS A record whenever
a change is detected. It runs well on a Raspberry Pi, Ubuntu, Debian, or any
modern Linux system with the prerequisites installed.

---

## Prerequisites

Only two tools are required:

| Tool | Purpose |
|------|---------|
| [curl](https://curl.se/) | HTTP requests (public IP lookup and Cloudflare API) |
| [jq](https://stedolan.github.io/jq/) | JSON parsing (config file and API responses) |

On Debian / Ubuntu:

```shell
sudo apt install curl jq
```

> **Note:** `dig` is no longer required. The current DNS record value is now
> fetched directly from the Cloudflare API, which is more accurate than a DNS
> lookup and eliminates DNS propagation lag.

---

## Installation

### Quick install (recommended)

Download the script directly into `/usr/local/bin` and make it executable
in one step:

```shell
sudo curl -fsSL \
  https://raw.githubusercontent.com/paulgit/cloudflare-ddns/master/cloudflare-ddns \
  -o /usr/local/bin/cloudflare-ddns \
  && sudo chmod +x /usr/local/bin/cloudflare-ddns
```

Once installed, the script is available system-wide as `cloudflare-ddns`.

> **Note:** Inspect the script before running it if you prefer:
> ```shell
> curl -fsSL https://raw.githubusercontent.com/paulgit/cloudflare-ddns/master/cloudflare-ddns | less
> ```

### Install from source

Clone the repository and symlink (or copy) the script into your `PATH`:

```shell
git clone https://github.com/paulgit/cloudflare-ddns.git
sudo ln -s "$(pwd)/cloudflare-ddns/cloudflare-ddns" /usr/local/bin/cloudflare-ddns
```

Or copy it instead of symlinking:

```shell
git clone https://github.com/paulgit/cloudflare-ddns.git
sudo cp cloudflare-ddns/cloudflare-ddns /usr/local/bin/cloudflare-ddns
sudo chmod +x /usr/local/bin/cloudflare-ddns
```

### Verify the installation

```shell
cloudflare-ddns --version
```

---

## Configuration

### File format

Configuration is stored as a **JSON file**. The default location is:

```
~/.config/cloudflare-ddns/cloudflare-ddns.json
```

This respects the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
If the environment variable `$XDG_CONFIG_HOME` is set, it is used as the base
instead of `~/.config`.

A different path can be specified at runtime with the `--config` flag (see
[Command-Line Options](#command-line-options) below).

### Creating the config file

Run the script once without a config file and it will create a template
automatically:

```shell
./cloudflare-ddns
```

The template will be written to the default location with permissions `600`.
Open it in your editor and fill in your values:

```json
{
  "auth_token": "YOUR_CLOUDFLARE_API_TOKEN",
  "zone_name": "example.com",
  "record_name": "ddns.example.com",
  "ip_check_url": "https://ipv4.icanhazip.com"
}
```

### Configuration fields

| Field | Required | Description |
|-------|----------|-------------|
| `auth_token` | Yes* | Cloudflare API Token (recommended) |
| `auth_email` | Yes* | Account e-mail for legacy Global API Key auth |
| `auth_key` | Yes* | Global API Key for legacy auth |
| `zone_name` | Yes | The apex domain managed in Cloudflare (e.g. `example.com`) |
| `record_name` | Yes | The A record to keep updated (e.g. `ddns.example.com`) |
| `ip_check_url` | Yes | URL that returns the public IPv4 address as plain text |

\* Provide either `auth_token` **or** both `auth_email` + `auth_key`.

### Authentication methods

#### Option A — API Token (recommended)

Create a scoped API Token at
<https://dash.cloudflare.com/profile/api-tokens> with the following
permissions:

- **Zone / DNS / Edit** — scoped to the specific zone you want to update

A scoped token limits the blast radius if the credential is ever leaked; it
can only edit DNS records in the zones you select.

```json
{
  "auth_token": "your-api-token-here",
  "zone_name": "example.com",
  "record_name": "ddns.example.com",
  "ip_check_url": "https://ipv4.icanhazip.com"
}
```

#### Option B — Legacy Global API Key

The Global API Key grants full access to your entire Cloudflare account. Use
this only if you cannot use API Tokens. The script will print a deprecation
warning each time it runs.

```json
{
  "auth_email": "you@example.com",
  "auth_key": "your-global-api-key-here",
  "zone_name": "example.com",
  "record_name": "ddns.example.com",
  "ip_check_url": "https://ipv4.icanhazip.com"
}
```

---

## Command-Line Options

```
Usage: cloudflare-ddns [OPTIONS]

Options:
  -h, --help              Show this help message and exit.
  --version               Print the version number and exit.
  --config PATH           Path to the JSON configuration file.
                          Default: ~/.config/cloudflare-ddns/
                                   cloudflare-ddns.json
  --dry-run               Run the full check (load config, auth,
                          fetch public IP, read current DNS IP)
                          but do not apply any DNS changes.
                          Logs and prints what would have changed.
  --no-color, --cron-mode Disable coloured output. Colour is
                          also suppressed automatically when
                          not attached to a terminal or when
                          the NO_COLOR env var is set.
```

### Examples

Use a custom config file:

```shell
./cloudflare-ddns --config /etc/cloudflare-ddns/config.json
```

Check what would happen without making any changes:

```shell
./cloudflare-ddns --dry-run
```

Combine with a custom config and no colour:

```shell
./cloudflare-ddns --dry-run --config /etc/cloudflare-ddns/config.json --no-color
```

Disable colour output explicitly:

```shell
./cloudflare-ddns --no-color
```

---

## Runtime Data

The script stores runtime data separately from the configuration:

| Path | Purpose |
|------|---------|
| `~/.cloudflare-ddns/cloudflare.ids` | Cached Cloudflare zone and record identifiers |
| `~/.cloudflare-ddns/cloudflare.log` | Timestamped log of all INFO / WARN / ERROR events |

The `~/.cloudflare-ddns/` directory is created automatically with permissions
`700` on first run.

### Identifier cache

On the first successful run the script fetches your zone and record
identifiers from the Cloudflare API and stores them in `cloudflare.ids`. On
subsequent runs these are loaded from the cache, avoiding an unnecessary API
call. The cache is regenerated automatically if it is deleted or found to be
incomplete.

### Log file

All events are appended to `cloudflare.log` with UTC ISO-8601 timestamps,
regardless of whether the terminal is a TTY. This makes the log useful when
the script is invoked from cron. Example entries:

```
2024-06-01T08:00:01Z [INFO] ddns.example.com: 1.2.3.4 -> 5.6.7.8
2024-06-01T08:05:01Z [WARN] ID cache missing or incomplete; fetching from API.
2024-06-01T09:10:01Z [ERROR] Public IP check returned invalid value: ''.
```

---

## Running from Cron

Add an entry to your crontab to run the script periodically. A check every
five minutes is a reasonable starting point:

```shell
crontab -e
```

```
*/5 * * * * /path/to/cloudflare-ddns --cron-mode
```

The `--cron-mode` flag (equivalent to `--no-color`) prevents ANSI colour
escape codes from appearing in cron mail. Colour is also disabled
automatically when the script detects it is not attached to a terminal, so
the flag is optional but recommended for clarity.

If you use a non-default config location, pass `--config` as well:

```shell
*/5 * * * * /path/to/cloudflare-ddns --cron-mode --config /etc/cloudflare-ddns/config.json
```

### Suppressing cron mail on no-change runs

The script produces **no output** when the IP address has not changed, so cron
will not send mail on the majority of runs. Output (and therefore mail) is
only generated when the record is updated, a warning is raised, or an error
occurs.

---

## Concurrency Protection

A per-user lock directory is created at `/tmp/cloudflare-ddns-<uid>.lock`
before any network activity begins. This prevents two cron instances from
running simultaneously if a previous invocation is still in progress (e.g.
due to a slow network). The lock is removed automatically on exit, including
on error.

---

## Colour Output

Colour is enabled automatically when the script's output is connected to a
terminal (TTY). It is suppressed in any of the following cases:

- The `NO_COLOR` environment variable is set (any value) — see <https://no-color.org/>
- The `--no-color` or `--cron-mode` flag is passed
- stdout and stderr are both redirected (e.g. cron, pipes)

---

## Security Notes

- The config file and identifier cache are both created and maintained with
  permissions `600` (owner read/write only).
- The config directory (`~/.config/cloudflare-ddns/`) and data directory
  (`~/.cloudflare-ddns/`) are maintained with permissions `700`.
- The config file is parsed as JSON via `jq` — it is never executed as shell
  code.
- API credentials are never written to the log file.
- Use an API Token (Option A) rather than the Global API Key: a token can be
  revoked independently and grants only the minimum required permission.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| `'jq' is required but not installed` | Install jq: `sudo apt install jq` |
| `Config file contains invalid JSON` | Syntax error in your config file — validate with `jq . ~/.config/cloudflare-ddns/cloudflare-ddns.json` |
| `No valid auth found` | `auth_token` (or `auth_email`/`auth_key`) still contains the placeholder value |
| `Zone '…' not found` | `zone_name` does not match any zone in your Cloudflare account |
| `Record '…' not found` | The A record does not exist in Cloudflare yet — create it manually first |
| `Another instance is already running` | A previous run is still active; or the lock was left behind — remove `/tmp/cloudflare-ddns-<uid>.lock` |
| `Failed to get public IP` | The `ip_check_url` is unreachable; try `curl https://ipv4.icanhazip.com` manually |
| DNS record keeps updating unexpectedly | Run with `--dry-run` to inspect what public IP and DNS IP are being detected without making changes |

---

## Credits

Thanks to [teddysun](https://github.com/teddysun) and others whose scripts
provided inspiration.

Written by Paul Git and Claude AI.

---

## Disclaimer

No warranties are given for correct function. Use at your own risk.