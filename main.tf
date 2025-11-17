terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.api_token
}

locals {
  services_file    = "${path.module}/services.json"
  services         = jsondecode(file(local.services_file))
  tunnel_hostname  = "${var.tunnel_id}.cfargotunnel.com"
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

resource "cloudflare_record" "tunnel_cname" {
  for_each = local.normalized_services

  zone_id = var.zone_id
  name    = each.value.label
  type    = "CNAME"
  content = local.tunnel_hostname
  proxied = var.proxied
  comment = "Managed by Terraform for ${each.value.hostname}"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

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
