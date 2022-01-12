terraform {
  backend "s3" {
    bucket = "dingi"
    key    = "dingi.tfstate"
    region = "ap-south-1"
  }
}
