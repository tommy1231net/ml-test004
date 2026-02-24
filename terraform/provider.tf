terraform {
  # 1.11.0 以上であれば 1.14.4 もOKにする設定
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  # プロジェクトIDとリージョンを変数参照に変更
  project = var.project_id
  region  = var.region
}
