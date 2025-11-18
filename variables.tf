variable "api_token" {
  description = "API token with permissions to manage Cloudflare DNS and Tunnels."
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID where the CNAMEs will be created."
  type        = string
}

variable "zone_name" {
  description = "Root domain name managed by the Cloudflare zone (e.g. example.com)."
  type        = string
}

variable "origin_address" {
  description = "Default hostname/IP for services (ex.: IP do host Docker). Pode ser sobrescrito por serviço via services[*].origin_address."
  type        = string
  default     = "localhost"
}

variable "proxied" {
  description = "Define se os registros CNAME ficam 'proxied' (nuvem laranja). Use false para expor diretamente e evitar cache/inspeção."
  type        = bool
  default     = true
}

variable "tunnel_name" {
  description = "Nome do Cloudflare Tunnel/Container que será criado automaticamente."
  type        = string
  default     = "cloudflarecasaos"
}
