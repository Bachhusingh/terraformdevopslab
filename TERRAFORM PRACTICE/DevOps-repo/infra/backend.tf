hcl
terraform {
  backend "s3" {
    bucket = "releaseops-tfstate-<your-unique-suffix>"
    key    = "envs/dev/terraform.tfstate"
    region = "ap-south-1"
    encrypt = true
    dynamodb_table = "releaseops-tf-locks"   # state locking ≈ Azure Storage blob lease
  }
}

Apply:
```bash
cd infra/envs/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan