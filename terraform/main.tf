# =================================================================
# Variable Definitions
# =================================================================
data "google_project" "project" {}

# =================================================================
# Service Account Definitions (Separation of Concerns)
# =================================================================

# Service Account for App Build and Deployment (Used by GitHub Actions via WIF)
resource "google_service_account" "deployer_sa" {
  account_id   = "${data.google_project.project.project_id}${var.deployer_sa_suffix}"
  display_name = "SA for GitHub Actions Deployment and Cloud Build"
}

# Service Account for App Execution (Used by Cloud Run instances)
resource "google_service_account" "runtime_sa" {
  account_id   = "${data.google_project.project.project_id}${var.runtime_sa_suffix}"
  display_name = "SA for Cloud Run Runtime"
}

# =================================================================
# Workload Identity Federation (WIF) Configuration
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

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# =================================================================
# Creation of Artifact Registry Repository
# =================================================================

resource "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = "${data.google_project.project.project_id}${var.apprepo_suffix}"
  description   = "Docker repository for ML App"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
}

# =================================================================
# IAM Role Configurations - Principle of Least Privilege (PoLP)
# =================================================================

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
# Cloud Run Configuration
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

resource "google_cloud_run_v2_service_iam_member" "cloud_run_public_access" {
  location = google_cloud_run_v2_service.model_api.location
  project  = google_cloud_run_v2_service.model_api.project
  name     = google_cloud_run_v2_service.model_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =================================================================
# Creation of Cloud Storage Bucket for Related Files
# (for HTML storage, independent of CI/CD)
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