module "environment" {
  source = "../../modules/environment"

  name      = "jsp-production"
  vpc_cidr  = "10.2.0.0/16"
  image_tag = var.image_tag
}
