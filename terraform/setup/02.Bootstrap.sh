# !!!Caution!!!
# Replace "XXXXX" to GCP Project ID

PROJECT_ID="ml-test004" #Replace Value

echo "--- Starting Bootstrap for ${PROJECT_ID} ---"

# Enable required APIs
echo "Enabling necessary APIs..."
gcloud services enable compute.googleapis.com \
                       storage.googleapis.com \
                       iam.googleapis.com \
                       cloudresourcemanager.googleapis.com \
                       cloudbuild.googleapis.com \
                       artifactregistry.googleapis.com \
                       run.googleapis.com

# Create a bucket for Terraform State
echo "Creating Terraform State bucket..."
gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
    --location=ASIA-NORTHEAST1 \
    --uniform-bucket-level-access \
    --enable-autoclass

# Enable versioning
gcloud storage buckets update gs://${PROJECT_ID}-tfstate --versioning

echo "--- Bootstrap Completed Successfully! ---"