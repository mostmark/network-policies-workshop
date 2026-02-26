#!/bin/bash

set -euo pipefail

# Check that oc CLI is available
if ! command -v oc &>/dev/null; then
  echo "Error: 'oc' CLI not found. Please install it first."
  exit 1
fi

# Check that user is logged in
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Please run 'oc login' first."
  exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Server: $(oc whoami --show-server)"
echo

# Install the Web Terminal operator
echo "=== Installing OpenShift Web Terminal Operator ==="
if oc get subscription web-terminal -n openshift-operators &>/dev/null; then
  echo "Web Terminal operator subscription already exists, skipping."
else
  oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: web-terminal
  namespace: openshift-operators
spec:
  channel: fast
  installPlanApproval: Automatic
  name: web-terminal
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "Web Terminal operator subscription created."
  echo "Waiting for operator to install..."
  for attempt in $(seq 1 30); do
    if oc get csv -n openshift-operators -o name 2>/dev/null | grep -q web-terminal; then
      PHASE=$(oc get csv -n openshift-operators -l operators.coreos.com/web-terminal.openshift-operators= -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
      if [ "$PHASE" = "Succeeded" ]; then
        echo "Web Terminal operator installed successfully."
        break
      fi
    fi
    if [ "$attempt" -eq 30 ]; then
      echo "Warning: Timed out waiting for Web Terminal operator. It may still be installing."
    fi
    sleep 60
  done
fi
echo

# Prompt for number of users
read -rp "Enter the number of users to prepare: " NUM_USERS

if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]] || [ "$NUM_USERS" -lt 1 ]; then
  echo "Error: Please enter a positive integer."
  exit 1
fi

# Promt for subdomain and user password
read -rp "Enter subdomain: " SUBDOMAIN
read -rp "Enter OpenShift user password: " PASSWORD

# Update the url and numbers of users in the manifests for 
# the username-distribution application
FILE="./username-distribution-app/overlays/dev/env-patch.yaml"

# Check if file exists
if [[ ! -f "$FILE" ]]; then
  echo "Error: File not found: $FILE"
  exit 1
fi

# Perform in-place substitutions using sed (cross-platform)
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' \
    -e "s|%SUBDOMAIN%|$SUBDOMAIN|g" \
    -e "s|%NUM_USERS%|$NUM_USERS|g" \
    -e "s|%PASSWORD%|$PASSWORD|g" \
    "$FILE"
else
  sed -i \
    -e "s|%SUBDOMAIN%|$SUBDOMAIN|g" \
    -e "s|%NUM_USERS%|$NUM_USERS|g" \
    -e "s|%PASSWORD%|$PASSWORD|g" \
    "$FILE"
fi

echo
echo "Preparing cluster for $NUM_USERS user(s)..."
echo

for i in $(seq 1 "$NUM_USERS"); do
  USER="user${i}"
  PROJECT_TEST="network-policy-test-${USER}"
  PROJECT_BACKEND="backend-team-${USER}"
  PROJECT_FRONTEND="frontend-team-${USER}"
  PROJECT_TERMINAL="terminal-${USER}"

  echo "=== Setting up $USER ==="

  # Create projects
  oc new-project "$PROJECT_TEST" --display-name="Network Policy Test - ${USER}" || true
  oc new-project "$PROJECT_BACKEND" --display-name="Backend Team - ${USER}" || true
  oc new-project "$PROJECT_FRONTEND" --display-name="Frontend Team - ${USER}" || true
  oc new-project "$PROJECT_TERMINAL" --display-name="Web Terminal - ${USER}" || true

  # Label frontend namespace for cross-namespace policy
  oc label namespace "$PROJECT_FRONTEND" team=frontend --overwrite

  # Grant admin role to user on all 3 projects + terminal project
  oc adm policy add-role-to-user admin "$USER" -n "$PROJECT_TEST"
  oc adm policy add-role-to-user admin "$USER" -n "$PROJECT_BACKEND"
  oc adm policy add-role-to-user admin "$USER" -n "$PROJECT_FRONTEND"
  oc adm policy add-role-to-user admin "$USER" -n "$PROJECT_TERMINAL"

# Pre-create and start the Web Terminal DevWorkspace
#  oc apply -f - <<EOF
# kind: DevWorkspace
# apiVersion: workspace.devfile.io/v1alpha2
# metadata:
#   name: terminal-web
#   namespace: ${PROJECT_TERMINAL}
#   finalizers:
#     - rbac.controller.devfile.io
#   annotations:
#     controller.devfile.io/devworkspace-source: web-terminal
#     controller.devfile.io/restricted-access: "true"
#   labels:
#     console.openshift.io/terminal: "true"
# spec:
#   started: true
#   routingClass: web-terminal
#   template:
#     components:
#     - name: web-terminal-exec
#       plugin:
#         kubernetes:
#           name: web-terminal-exec
#           namespace: openshift-operators
#     - name: web-terminal-tooling
#       plugin:
#         kubernetes:
#           name: web-terminal-tooling
#           namespace: openshift-operators
# EOF

  echo "Done with $USER"
  echo
done

# Deployment of the user distribution application
echo
echo "Deploying the user distribution application..."
echo

oc new-project user-distribution --display-name="User distribution application"
oc apply -k username-distribution-app/overlays/dev

# Deployment of the lab guide
echo
echo "Deploying the lab guide application..."
echo

oc new-project lab-guide --display-name="Lab guide application"
oc create -f lab-guide-app/

echo "============================================"
echo "Cluster preparation complete!"
echo "Created projects for $NUM_USERS user(s)."
echo "Each user has admin access to their 4 projects."
echo "============================================"
