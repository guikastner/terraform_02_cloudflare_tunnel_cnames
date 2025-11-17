output "service_hostnames" {
  description = "Fully-qualified hostnames created for each Docker service."
  value = {
    for name, svc in local.normalized_services :
    name => svc.hostname
  }
}
