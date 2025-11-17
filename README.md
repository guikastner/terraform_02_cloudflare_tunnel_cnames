# Terraform - Cloudflare Tunnel CNAMEs

Projeto Terraform/OpenTofu que cria os registros CNAME necessários na zona do Cloudflare e mantém a configuração de ingress do Tunnel para encaminhar portas de containers Docker executando no host local. Os exemplos de comando abaixo usam o binário `tofu`, mas é possível substituir por `terraform` caso prefira.

## Pré-requisitos
- OpenTofu `>= 1.5` (ou Terraform compatível)
- Token de API do Cloudflare com permissões para **DNS:Edit** e **Cloudflare Tunnel:Edit**
- Tunnel já existente criado via `cloudflared tunnel create` (o Terraform apenas referencia o `tunnel_id`)

## Estrutura dos arquivos
- `main.tf` &mdash; provedor, registros DNS e configuração do Tunnel
- `variables.tf` &mdash; definição das variáveis necessárias
- `outputs.tf` &mdash; hostnames expostos após o `apply`
- `terraform.tfvars.example` &mdash; exemplo que pode ser copiado para `terraform.tfvars`
- `services.json` &mdash; mapa versionado com todos os serviços publicados pelo tunnel

## Configuração
1. Copie o arquivo de exemplo: `cp terraform.tfvars.example terraform.tfvars`
2. Preencha `terraform.tfvars` com seus valores reais (IDs do account/zone/tunnel)
3. Edite `services.json` para incluir/alterar os serviços (exemplo abaixo)
4. Exporte o token sem gravar em disco, por exemplo:
   ```bash
   export TF_VAR_api_token=$(grep CLOUDFLARE_API_TOKEN .env | cut -d'=' -f2-)
   # ou
   export TF_VAR_api_token="seu_token"
   ```
5. Opcional: salve as demais variáveis em `.env` e carregue com `set -a; source .env; set +a`

## Variáveis principais
- `api_token` &mdash; token de API (use variável de ambiente `TF_VAR_api_token`)
- `account_id` &mdash; ID da conta Cloudflare
- `zone_id` &mdash; ID da zona onde os CNAMEs serão criados
- `zone_name` &mdash; domínio base (ex.: `midominio.com`)
- `origin_address` &mdash; IP/hostname padrão do host que executa os containers. Caso algum serviço precise de um destino diferente, sobrescreva com `services["nome"].origin_address`.
- `proxied` &mdash; define se os registros ficam atrás do proxy da Cloudflare (nuvem laranja). Use `false` para evitar cache/proxy nos CNAMEs.
- `tunnel_id` &mdash; ID do tunnel criado previamente
- `services.json` &mdash; arquivo versionado em JSON que descreve o mapa dos serviços publicados. Cada chave representa um identificador (ou subdomínio) e aceita os campos:
  - `subdomain` (opcional) &mdash; sobrescreve o nome da chave quando quiser usar outro subdomínio
  - `port` (obrigatório) &mdash; porta exposta pelo container Docker
  - `origin_address` (opcional) &mdash; IP/hostname alternativo caso queira ignorar o padrão definido em `var.origin_address`
  - `origin_protocol` (opcional, default `http`) &mdash; protocolo aceito por Cloudflare (`http`, `https`, `tcp`, `ssh`, etc.)

### Exemplo de `services.json`
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
  }
}
```

## Controle de versão
O repositório já contém um `.gitignore` alinhado às boas práticas do Terraform/OpenTofu:
- ignora diretórios de trabalho (`.terraform`, `.terraform.d`, `.tofu`)
- evita versionar estados, `tfvars` e arquivos de override que podem conter segredos
- cobre arquivos de configuração locais (`.terraformrc`, `.tofurc`) e artefatos de plan/apply (`*.tfplan`)

Assim, apenas o código declarativo e o `terraform.tfvars.example` ficam sob controle de versão.

## Execução
```bash
tofu init
tofu plan
tofu apply
```

Após o `apply`, cada entrada em `services` terá:
- um registro CNAME apontando para `<tunnel_id>.cfargotunnel.com`
- uma regra de ingress dentro do recurso `cloudflare_zero_trust_tunnel_cloudflared_config` que redireciona o hostname para o serviço/porta informados

Os hostnames provisionados são exibidos em `tofu output service_hostnames` (ou `terraform output service_hostnames`).
