# =================================================================
# 1. 変数定義
# =================================================================
data "google_project" "project" {}

# =================================================================
# 2. サービスアカウントの定義 (役割の分離)
# =================================================================

# アプリデプロイ兼ビルド用SA (GitHub ActionsからWIFで利用)
resource "google_service_account" "deployer_sa" {
  account_id   = "${data.google_project.project.project_id}${var.deployer_sa_suffix}"
  display_name = "SA for GitHub Actions Deployment and Cloud Build"
}

# アプリ実行用SA (Cloud Runインスタンスが使用)
resource "google_service_account" "runtime_sa" {
  account_id   = "${data.google_project.project.project_id}${var.runtime_sa_suffix}"
  display_name = "SA for Cloud Run Runtime"
}

# =================================================================
# 3. Workload Identity Federation (WIF) の設定
# =================================================================

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "${var.wif_pool_id}"
  display_name              = "GitHub Pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "${data.google_project.project.project_id}${var.wif_provider_suffix}"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "attribute.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# デプロイ用SAにGitHubリポジトリを「ユーザー」として紐付ける
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# =================================================================
# 4. Artifact Registry リポジトリの作成
# =================================================================

resource "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = "${data.google_project.project.project_id}${var.apprepo_suffix}"
  description   = "Docker repository for ML App"
  format        = "DOCKER"

  # 古いイメージを自動削除する設定（最新の3つだけ残す）
  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
}

# =================================================================
# 5. 権限（IAM）の設定 - 最小権限の原則
# =================================================================

# 【デプロイ用SAへの権限付与】
locals {
  deployer_roles = [
    "roles/cloudbuild.builds.editor",
    "roles/artifactregistry.writer",
    "roles/run.developer",
    "roles/logging.logWriter",
    "roles/storage.objectAdmin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/iam.serviceAccountUser"
  ]
}

resource "google_project_iam_member" "deployer_iam" {
  for_each = toset(local.deployer_roles)
  project  = data.google_project.project.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer_sa.email}"
}

# デプロイ用SAが「自分自身」と「実行用SA」を利用するための権限 (actAs)
resource "google_service_account_iam_member" "allow_impersonation" {
  for_each = {
    deployer = google_service_account.deployer_sa.name
    runtime  = google_service_account.runtime_sa.name
  }
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer_sa.email}"
}

# =================================================================
# 6. Cloud Run設定
# =================================================================
resource "google_cloud_run_v2_service" "model_api" {
  name     = "${data.google_project.project.project_id}${var.cloud_run_suffix}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.runtime_sa.email
    
    scaling {
      max_instance_count = 1
    }

    annotations = {
      "run.googleapis.com/startup-cpu-boost" = "true"
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
    timeout = "300s"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].annotations,
      template[0].labels,
      client,
      client_version,
    ]
  }

  depends_on = [google_artifact_registry_repository.app_repo]
  
  labels = {
    "managed-by" = "github-actions"
  }
}

# Cloud Run V2 サービスを一般公開（未認証アクセス許可）にする設定
resource "google_cloud_run_v2_service_iam_member" "cloud_run_public_access" {
  location = google_cloud_run_v2_service.model_api.location
  project  = google_cloud_run_v2_service.model_api.project
  name     = google_cloud_run_v2_service.model_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =================================================================
# 7. 関連ファイル公開用バケットの作成（CI/CDとは無関係）
# =================================================================

resource "google_storage_bucket" "public_bucket" {
  name          = "${data.google_project.project.project_id}${var.public_bucket_suffix}"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  autoclass {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ANY"
    }
  }
}