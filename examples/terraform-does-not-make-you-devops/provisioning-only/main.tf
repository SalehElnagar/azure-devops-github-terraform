module "workload_foundation" {
  source = "../modules/workload-foundation"

  name_prefix          = var.name_prefix
  environment          = "dev"
  location             = var.location
  owner                = var.owner
  expires_on           = var.expires_on
  operating_model      = "ticket-driven"
  enable_observability = false
  enable_recovery      = false
  enable_delete_lock   = false

  tags = {
    delivery_path = "manual-request"
    state_model   = "local"
  }
}
