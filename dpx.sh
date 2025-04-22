#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# IMPORTANT: Fly.io app names must be globally unique!
# You might need to change this name if 'chat-hub-from-github' is taken.
FLY_APP_NAME="chat-hub-from-github"
# Choose a Fly.io region (e.g., fra for Frankfurt, ams for Amsterdam, lhr for London)
FLY_REGION="fra"
# Define secrets here (or prompt user)
ALLOWED_TOKENS_SECRET="tokenA,tokenB"
REDIS_URL_SECRET="" # Keeping this empty as before

# Get GitHub repository URL from user
read -p "Enter the URL of your GitHub repository (e.g., https://github.com/user/repo.git): " GITHUB_REPO_URL
if [ -z "$GITHUB_REPO_URL" ]; then
    echo "Error: GitHub repository URL cannot be empty."
    exit 1
fi

# Define the directory name for cloning (derived from app name)
CLONE_DIR="${FLY_APP_NAME}_repo"

echo "--- Configuration ---"
echo "Fly App Name:     ${FLY_APP_NAME}"
echo "Fly Region:       ${FLY_REGION}"
echo "GitHub Repo URL:  ${GITHUB_REPO_URL}"
echo "Clone Directory:  ${CLONE_DIR}"
echo "---------------------"
echo "IMPORTANT: Ensure 'flyctl' is installed, you are logged in ('fly auth login'),"
echo "           and your environment can clone the GitHub repo (check auth for private repos)."
read -p "Press Enter to continue, or Ctrl+C to cancel..."

# 1. CLEANUP & CLONE REPOSITORY
echo "--- Cloning GitHub Repository ---"
# Remove existing directory if it exists to ensure fresh clone
if [ -d "${CLONE_DIR}" ]; then
  echo "Removing existing directory: ${CLONE_DIR}"
  rm -rf "${CLONE_DIR}"
fi

# Clone the repository
echo "Cloning ${GITHUB_REPO_URL} into ${CLONE_DIR}..."
git clone "${GITHUB_REPO_URL}" "${CLONE_DIR}"

# Enter the cloned directory
cd "${CLONE_DIR}"
echo "Entered directory: $(pwd)"

# Check if Dockerfile exists (basic validation)
if [ ! -f "Dockerfile" ]; then
    echo "Error: Dockerfile not found in the root of the cloned repository."
    echo "Please ensure Dockerfile exists in your repository: ${GITHUB_REPO_URL}"
    cd .. # Go back to parent directory before exiting
    exit 1
fi

# 2. GENERATE fly.toml CONFIGURATION (inside repo directory)
echo "--- Generating fly.toml ---"
cat > fly.toml << EOF
# fly.toml app configuration file generated for ${FLY_APP_NAME}
# See https://fly.io/docs/reference/configuration/ for information about how to use this file.

app = "${FLY_APP_NAME}"
primary_region = "${FLY_REGION}"

[build]
  # Assumes Dockerfile is in the root of the repository
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 8000      # Your app's internal listening port (from Dockerfile CMD)
  force_https = true
  auto_stop_machines = true # Enable scale-to-zero for free tier
  auto_start_machines = true
  min_machines_running = 0  # Allow stopping machines

  # Health check for FastAPI (assumes /health endpoint exists in your app.py)
  [[http_service.checks]]
    interval = "15s"
    timeout = "5s"
    grace_period = "10s"
    method = "get"
    path = "/health"
    protocol = "http"
EOF

echo "fly.toml created in $(pwd)."

# 3. SET SECRETS (using flyctl)
echo "--- Setting Fly.io Secrets ---"
echo "Setting ALLOWED_TOKENS..."
fly secrets set -a ${FLY_APP_NAME} ALLOWED_TOKENS="${ALLOWED_TOKENS_SECRET}"
echo "Setting REDIS_URL..."
fly secrets set -a ${FLY_APP_NAME} REDIS_URL="${REDIS_URL_SECRET}"
echo "Secrets set."

# 4. DEPLOY APPLICATION (using flyctl from repo directory)
echo "--- Deploying Application to Fly.io ---"
# fly deploy reads fly.toml and uses Dockerfile from the current directory
fly deploy -a ${FLY_APP_NAME} --remote-only

echo "Deployment command finished."

# 5. SHOW STATUS & URL
echo "--- Application Status ---"
fly status -a ${FLY_APP_NAME}

APP_HOSTNAME=$(fly status -a ${FLY_APP_NAME} --json | grep '"Hostname":' | awk -F '"' '{print $4}')

echo "-----------------------------------------------------"
echo "Chat hub deployment from GitHub to Fly.io initiated!"
if [ -n "$APP_HOSTNAME" ]; then
  echo "Application Hostname: ${APP_HOSTNAME}"
  echo "Connect using a WebSocket client:"
  echo "wss://${APP_HOSTNAME}/ws/tokenA" # Assumes tokenA is valid based on secrets
  echo "Health Check URL: https://${APP_HOSTNAME}/health"
else
  echo "Could not retrieve hostname automatically. Check 'fly status -a ${FLY_APP_NAME}' manually."
fi
echo "-----------------------------------------------------"

# Go back to the parent directory
cd ..

echo "Script finished."
