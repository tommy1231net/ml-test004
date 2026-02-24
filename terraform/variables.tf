variable "project_id" {
  description = "GCP Project ID"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "project_number" {
  description = "GCP Project Number"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "region" {
  description = "GCP Region"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "github_repo" {
  description = "GitHub Repository"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "deployer_sa_suffix" {
  description = "Build & Deploy Service Account ID"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "runtime_sa_suffix" {
  description = "Cloud Run Service Account ID"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "wif_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "wif_provider_suffix" {
  description = "Workload Identity Provider ID"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "model_bucket_suffix" {
  description = "GCS Bucket Name for Model Files"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "build_bucket_suffix" {
  description = "GCS Bucket Name for Build Files"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "public_bucket_suffix" {
  description = "GCS Bucket Name for Public Files"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "apprepo_suffix" {
  description = "Artifact Registry Name"
  type        = string
  #terraform.tfvarsで値は設定
}

variable "cloud_run_suffix" {
  description = "Name of Cloud Run"
  type        = string
  #terraform.tfvarsで値は設定
}