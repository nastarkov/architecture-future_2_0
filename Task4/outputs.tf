output "network_id" { value = yandex_vpc_network.platform.id }
output "lakehouse_bucket" { value = yandex_storage_bucket.lakehouse.bucket }
output "runtime_lockbox_secret_id" { value = yandex_lockbox_secret.platform.id }
output "bastion_public_ip" { value = yandex_compute_instance.bastion.network_interface[0].nat_ip_address }
output "portal_load_balancer_ip" {
  value = one([
    for listener in yandex_lb_network_load_balancer.portal.listener : one([
      for address_spec in listener.external_address_spec : address_spec.address
    ])
    if listener.name == "http"
  ])
}
output "metadata_postgresql_fqdn" {
  value = one([for host in yandex_mdb_postgresql_cluster.metadata.host : host.fqdn])
}
output "platform_internal_ips" {
  value = { for name, vm in yandex_compute_instance.platform : name => vm.network_interface[0].ip_address }
}
