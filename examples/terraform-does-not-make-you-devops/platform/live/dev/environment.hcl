locals {
  environment     = "dev"
  location        = get_env("LAB_LOCATION", "canadacentral")
  name_prefix     = get_env("LAB_NAME_PREFIX")
  owner           = get_env("LAB_OWNER")
  expires_on      = get_env("LAB_EXPIRES_ON")
  lifecycle_phase = get_env("LAB_LIFECYCLE_PHASE", "operate")

  address_space   = ["10.52.0.0/16"]
  subnet_prefixes = ["10.52.1.0/24"]
}
