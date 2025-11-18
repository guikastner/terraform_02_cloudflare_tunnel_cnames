terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.api_token
}

provider "docker" {}

provider "random" {}

locals {
  services_file    = "${path.module}/services.json"
  services         = jsondecode(file(local.services_file))
  normalized_services = {
    for name, svc in local.services :
    name => {
      label           = coalesce(try(svc.subdomain, null), name)
      hostname        = format("%s.%s", coalesce(try(svc.subdomain, null), name), var.zone_name)
      origin_protocol = lower(coalesce(try(svc.origin_protocol, null), "http"))
      origin_address  = coalesce(try(svc.origin_address, null), var.origin_address, "localhost")
      port            = svc.port
    }
  }
  ordered_services = [
    for key in sort(keys(local.normalized_services)) :
    local.normalized_services[key]
  ]
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cloudflared" {
  account_id = var.account_id
  name       = var.tunnel_name
  secret     = random_id.tunnel_secret.b64_std
}

resource "docker_image" "cloudflared" {
  name         = "cloudflare/cloudflared:latest"
  keep_locally = false
}

resource "docker_network" "cloudflared_bridge" {
  name   = "${var.tunnel_name}-bridge"
  driver = "bridge"
}

resource "cloudflare_record" "tunnel_cname" {
  for_each = local.normalized_services

  zone_id = var.zone_id
  name    = each.value.label
  type    = "CNAME"
  content = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.cloudflared.id)
  proxied = var.proxied
  comment = "Managed by Terraform for ${each.value.hostname}"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cloudflared.id

  config {
    dynamic "ingress_rule" {
      for_each = local.ordered_services
      content {
        hostname = ingress_rule.value.hostname
        service  = format("%s://%s:%d", ingress_rule.value.origin_protocol, ingress_rule.value.origin_address, ingress_rule.value.port)
      }
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "docker_container" "cloudflarecasaos" {
  name         = var.tunnel_name
  image        = docker_image.cloudflared.image_id
  restart      = "unless-stopped"

  networks_advanced {
    name = docker_network.cloudflared_bridge.name
  }

  host {
    host = "host.docker.internal"
    ip   = var.origin_address
  }

  command = [
    "tunnel",
    "--no-autoupdate",
    "run",
    "--token",
    cloudflare_zero_trust_tunnel_cloudflared.cloudflared.tunnel_token
  ]

  depends_on = [
    cloudflare_zero_trust_tunnel_cloudflared_config.this,
    docker_network.cloudflared_bridge
  ]
}
