# Module is used to define things in one place
# and achieve DRY
module "vm" {
  source = "../../modules/openstack_vm"

  name         = "staging-docker"
  image        = "Ubuntu 22.04"
  flavor       = "m1.extra_large"
  public_key   = var.ssh_public_key
  network_name = "DHBW"

  # No public floating-IP pool is usable from off-campus on this OpenStack;
  # deploy reaches the VM via its fixed IP on the network (requires the
  # operator to be in the network / a full-tunnel VPN). Flip to true and set
  # floating_ip_pool when a routable pool is available.
  assign_floating_ip = false

  security_groups = ["default", "appstore-deploy"]

  docker_data_volume_size_gb = 0

  metadata = {
    env  = "staging"
    role = "docker"
  }
}

output "vm_ip" {
  value = module.vm.vm_ip
}