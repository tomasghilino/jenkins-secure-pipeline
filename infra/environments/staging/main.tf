module "environment" {
  source = "../../modules/environment"

  name      = "jsp-staging"
  vpc_cidr  = "10.0.0.0/16"
  image_tag = var.image_tag
}
