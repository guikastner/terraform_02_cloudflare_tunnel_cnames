# Cloudflare Tunnel CNAMEs (Terraform/OpenTofu)

Infrastructure as code project that provisions every DNS record and tunneling rule needed to expose containers running on your host through a Cloudflare Tunnel. All commands use the OpenTofu CLI (`tofu`), but you can swap it for HashiCorp Terraform (`terraform`) with no additional changes.

## Requirements
- OpenTofu `>= 1.5` or Terraform with the same language level
- Cloudflare API token with **DNS:Edit** and **Cloudflare Tunnel:Edit** scopes
- An existing tunnel created with `cloudflared tunnel create` (this project only references the `tunnel_id`)

## Repository layout
- `main.tf` &mdash; provider configuration, DNS records, and tunnel rules
- `variables.tf` &mdash; list of required inputs
- `outputs.tf` &mdash; hostnames exposed via Terraform outputs
- `terraform.tfvars.example` &mdash; template you can copy to `terraform.tfvars`
- `services.json` &mdash; versioned map describing every service that should be published through the tunnel

## Where to find Cloudflare values
- `account_id` &mdash; open the Cloudflare dashboard, select your account, and copy the ID that appears in the URL (`dash.cloudflare.com/<account_id>`). You can also find it under **Workers & Pages &gt; Overview**.
- `zone_id` &mdash; select the desired domain in the dashboard and look at **Overview &gt; API &gt; Zone ID**.
- `tunnel_id` &mdash; run `cloudflared tunnel list` on the host or open **Zero Trust Dashboard &gt; Networks &gt; Tunnels**, click the tunnel, and copy the UUID.
- `api_token` &mdash; create a scoped token in **My Profile &gt; API Tokens** that includes DNS:Edit and Cloudflare Tunnel:Edit permissions for the target zone/account.

## Configuration
1. Copy the defaults: `cp terraform.tfvars.example terraform.tfvars`.
2. Fill `terraform.tfvars` with your account/zone/tunnel IDs, the default origin address, and whether CNAMEs should be proxied or not.
3. Edit `services.json` and list every service you want to expose (sample below). The file is safe to commit because it contains no secrets.
4. Export the API token without writing it to disk, e.g.:
   ```bash
   export TF_VAR_api_token=$(grep CLOUDFLARE_API_TOKEN .env | cut -d'=' -f2-)
   # or
   export TF_VAR_api_token="your_token_here"
   ```
5. Optionally store the other variables in `.env` and load them with `set -a; source .env; set +a`.

## Main variables
- `api_token` &mdash; Cloudflare API token (pass via `TF_VAR_api_token` to keep it secret).
- `account_id` &mdash; Cloudflare account that owns the tunnel.
- `zone_id` &mdash; DNS zone where the CNAMEs will be created.
- `zone_name` &mdash; base domain, e.g. `example.com`.
- `origin_address` &mdash; default IP/hostname reached by `cloudflared` inside your network. Individual services can override it.
- `proxied` &mdash; toggles the orange-cloud proxy. Set to `false` to avoid Cloudflare caching and expose the tunnel directly.
- `tunnel_id` &mdash; UUID of the existing tunnel.
- `services.json` &mdash; versioned JSON file that describes every published service. Each entry accepts:
  - `subdomain` (optional) &mdash; overrides the key name in case you need a different label.
  - `port` (required) &mdash; container port listening on the host.
  - `origin_address` (optional) &mdash; target IP/hostname for that specific service.
  - `origin_protocol` (optional) &mdash; defaults to `http`, but supports `https`, `tcp`, `ssh`, etc.

### Example `services.json`
```json
{
  "grafana": {
    "port": 3000
  },
  "traefik": {
    "subdomain": "proxy",
    "port": 8080,
    "origin_protocol": "http",
    "origin_address": "docker.internal"
  },
  "romm": {
    "port": 8000,
    "origin_protocol": "https"
  },
  "mqtt": {
    "port": 1883,
    "origin_protocol": "tcp"
  }
}
```

## How Cloudflare tunneling works
1. You run `cloudflared` on your host/container and authenticate it with the `tunnel_id`.
2. Each hostname defined here becomes a CNAME that points to `<tunnel_id>.cfargotunnel.com`.
3. When a client resolves `app.example.com`, the DNS response directs it to Cloudflare's network, which already knows how to reach your `cloudflared` instance.
4. The `cloudflare_zero_trust_tunnel_cloudflared_config` resource keeps the ingress rules synced so that Cloudflare forwards `app.example.com` traffic to `origin_protocol://origin_address:port`.
5. If the proxy is disabled (`proxied = false`), the request still routes through the tunnel but Cloudflare skips caching/inspection.

## Version control
The repository ships with a `.gitignore` tuned for Terraform/OpenTofu:
- ignores `.terraform`, `.terraform.d`, `.tofu`, state files, and auto tfvars
- excludes override files, CLI configs, and plan artifacts

Only declarative code and `terraform.tfvars.example` are meant to be committed.

## Running the project
```bash
tofu init     # or: terraform init
tofu plan     # or: terraform plan
tofu apply    # or: terraform apply
```

After `apply`, each service listed in `services.json` will have:
- a CNAME record pointing to `<tunnel_id>.cfargotunnel.com`
- a matching ingress rule managed by `cloudflare_zero_trust_tunnel_cloudflared_config`

You can list the hostnames with `tofu output service_hostnames` (or `terraform output service_hostnames`).
