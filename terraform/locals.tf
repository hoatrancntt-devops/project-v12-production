locals {
  cfg            = yamldecode(file("${path.module}/../project-config.yml"))
  project_slug   = replace(lower(local.cfg.project_name), "_", "-")
  vm_template_id = try(local.cfg.vm_template_id, 9000)
}
