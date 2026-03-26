locals {
  cfg = yamldecode(file("${path.module}/../project-config.yml"))
}
