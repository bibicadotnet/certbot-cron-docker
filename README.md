# Certbot Cron Docker

Dockerised Certbot that utilises cron to schedule creating and renewing SSL certificates. Supports standalone, webroot or Cloudflare methods. Automatic renewal attempt happens every 6 hours by default.

## Tags

I use the [Feature Branch](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow) workflow. The `latest` tag contains all of the latest changes that have been merged from individual feature branches. Feature branches are squashed into `master`.

Pinned releases are created by creating a tag off `master` to capture the repo in a particular state. They are recommended for stability.

## Running

### Docker CLI
```bash
docker run -d --name certbot \
    -e EMAIL=admin@domain.com \
    -e DOMAINS=domain.com \
    -e PLUGIN=cloudflare \
    -e CLOUDFLARE_TOKEN=123abc
    -v ./certbot-cron:/config \
    git.mrmeeb.stream/mrmeeb/certbot-cron:latest
```

### Docker Compose
```yaml
version: "3"
services:
  certbot:
    image: git.mrmeeb.stream/mrmeeb/certbot-cron:latest
    container_name: certbot
    restart: unless-stopped
    volumes:
      - ./certbot:/config
    environment:
      - EMAIL=admin@domain.com
      - DOMAINS=domain.com,*.domain.com
      - PLUGIN=cloudflare
      - CLOUDFLARE_TOKEN=123abc
```

## Environment Variables:

### Core Options:

Core options to the container

| Variable | Default | Description |
| --- | --- | --- |
|PUID    |int    |1000   |Sets the UID of the user certbot runs under |
|PGID    |int    |1000   |Sets the GID of the user certbot runs under |
|TZ      |[List of valid TZs](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List)    |UTC    |Sets the timezone of the container |
| ONE_SHOT | false | Whether container exits after first run of certbot, or starts cron-based auto-renewal |
| GENERATE_DHPARAM | true (case-sensitive) | Generate Diffie-Hellman keys in /config/letsencrypt/keys |
| INTERVAL | 0 */6 * * * | How often certbot attempts to renew the certificate. Cron syntax |
| CERT_COUNT | 1 | How many certificates certbot will try to issue. [Details here](https://git.mrmeeb.stream/MrMeeb/certbot-cron-docker#multiple-certificates) |
| APPRISE_URL | None | URL for Apprise notifications. [Syntax](https://github.com/caronc/apprise?tab=readme-ov-file#supported-notifications)
| NOTIFY_ON_SUCCESS | false | Notify on a successful renewal attempt. Note that this isn't just when the cert is renewed, but on every renewal attempt. |
| NOTIFY_ON_FAILURE | false | Notify on a failed renewal attempt.

### Certificate Options

These options apply when `CERT_COUNT` is `1`

| Variable | Default | Description |
| --- | --- | --- |
| EMAIL | None | Email address for renewal information & other communications |
| DOMAINS | None | Domains to be included in the certificate. Comma separated list, no spaces. Wildcards supported |
| STAGING | false (case-sensitive) | Uses the LetsEncrypt staging endpoint for testing - avoids the aggressive rate-limiting of the production endpoint. **Not supported when using a custom Certificate Authority.** |

### Plugins

Plugins that can used for issuing a certificate

| Variable | Default | Description |
| --- | --- | --- |
| PLUGIN | standalone | Options are `webroot`, `standalone`, or `cloudflare` |

- `webroot` - relies on a webserver running on the FQDN for which you're trying to issue a certificate to serve validation files
  - Requires the webserver's root directory to be mounted to the container as `/config/webroot`
- `standalone` - certbot spawns a webserver on port 80 for validation
  - Requires this container to be bound to port 80 on the host
- `cloudflare` - Creates a TXT record with Cloudflare pointing to the domain you're requesting a certificate for
  - Requires the domain you're requesting a certificate for to be entered in Cloudflare

#### Cloudflare Plugin

Options that affect the behaviour of certbot running with the Cloudflare plugin

| Variable | Default | Description |
| --- | --- | --- |
| PROPOGATION_TIME | 10 | The amount of time (seconds) that certbot waits for the TXT records to propogate to Cloudflare before verifying - the more domains in the certificate, the longer you might need |
| CLOUDFLARE_TOKEN | null | Cloudflare token for verification |

### Custom Certificate Authority

Options to use a custom Certificate Authority, for example when issuing internal certificates

| Variable | Default | Description |
| --- | --- | --- |
| CUSTOM_CA | null | Name of the root certificate Certbot/ACME will trust requesting the certificate, e.g `root.pem`. **Must be placed in `/config/custom_ca`** |
| CUSTOM_CA_SERVER | null | Custom server URL used by Certbot/ACME when requesting a certificate, e.g `https://ca.internal/acme/acme/directory` |

### Multiple Certificates

This container can issue multiple certificates each containing different domains. This could be used to issue a certificate for a public domain on Cloudflare, but then also for a local certificate from an internal Certificate Authority, for example. Another example would be you have a web-server hosting two separate websites and you want them to have dedicated SSL certificates instead of sharing one.

When issuing multiple certificates, first `CERT_COUNT` must be set to a value greater than 1.

#### Global Environment Variables 

Some environment variables can be set globally, where they apply to all certificates (unless otherwise specifically specified). The following can be used globally:

| Variable | DESCRIPTION |
| --- | --- |
|EMAIL| Email address for renewal information & other communications |
|STAGING| Uses the LetsEncrypt staging endpoint for testing - avoids the aggressive rate-limiting of the production endpoint. **Not supported when using a custom Certificate Authority.** |
|CUSTOM_CA| Name of the root certificate Certbot/ACME will trust requesting the certificate, e.g `root.pem`. **Must be placed in `/config/custom_ca`** |
|CUSTOM_CA_SERVER| Custom server URL used by Certbot/ACME when requesting a certificate, e.g `https://ca.internal/acme/acme/directory` |
|PLUGIN| Options are `webroot`, `standalone`, or `cloudflare` |
|PROPOGATION_TIME| **(Applies to Cloudflare plugin)** The amount of time (seconds) that certbot waits for the TXT records to propogate to Cloudflare before verifying - the more domains in the certificate, the longer you might need |

More detail on these environment variables may be found further up.

#### Certificate-specific Environment Variables

Any variable other than those described as **Core Options** can be set per-certificate in a multi-certificate environment. The syntax is `${VARIABLE_NAME}_${CERT_NUMBER}`. The only certificate-specific option that **must** be set is the `DOMAINS` option.

##### Multi-certificate container using global variables:

```yaml
  certbot:
    container_name: certbot
    image: git.mrmeeb.stream/mrmeeb/certbot-cron
    volumes:
      - /docker/certbot-cron:/config
      - /docker/nginx/www:/config/webroot
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - GENERATE_DHPARAM=false
      - CERT_COUNT=2
      - EMAIL=admin@domain.com
      - CUSTOM_CA=root.pem
      - CUSTOM_CA_SERVER=https://ca.internal/acme/acme/directory
      - PLUGIN=webroot
      - STAGING=false
      - DOMAINS_1=website1.com
      - DOMAINS_2=website2.com
```

##### Multi-certificate container using different options for each certificate:
```yaml
  certbot:
    container_name: certbot
    image: git.mrmeeb.stream/mrmeeb/certbot-cron
    volumes:
      - /docker/certbot-cron:/config
      - /docker/nginx/www:/config/webroot
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - GENERATE_DHPARAM=false
      - CERT_COUNT=2
      - EMAIL=admin@domain.com
      - DOMAINS_1=website1.com
      - CUSTOM_CA_1=root.pem
      - CUSTOM_CA_SERVER_1=https://ca.internal/acme/acme/directory
      - PLUGIN_1=webroot
      - STAGING_1=false
      - DOMAINS_2=website2.com
      - PLUGIN_2=cloudflare
      - CLOUDFLARE_TOKEN_2=abc123
      - PROPOGATION_TIME_2=30
      - STAGING_2=true
```

## Volumes

| Docker path | Purpose |
| --- | --- |
| /config | Stores configs and LetsEncrypt output for mounting in other containers
| /config/webroot | Mountpoint for the webroot of a separate webserver. **Required if `PLUGIN=webroot` is set**

## Ports

| Port | Purpose |
| --- | --- |
| 80 | Used by ACME to verify domain ownership. **Required if `PLUGIN=standalone` is set**