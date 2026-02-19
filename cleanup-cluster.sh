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

# Prompt for number of users
read -rp "Enter the number of users to clean up: " NUM_USERS

if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]] || [ "$NUM_USERS" -lt 1 ]; then
  echo "Error: Please enter a positive integer."
  exit 1
fi

echo
echo "WARNING: This will delete all workshop projects for $NUM_USERS user(s) and uninstall the Web Terminal operator."
read -rp "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != [yY] ]]; then
  echo "Aborted."
  exit 0
fi

echo
echo "Cleaning up cluster..."
echo

for i in $(seq 1 "$NUM_USERS"); do
  USER="user${i}"
  echo "=== Removing projects for $USER ==="

  oc delete project "network-policy-test-${USER}" --ignore-not-found
  oc delete project "backend-team-${USER}" --ignore-not-found
  oc delete project "frontend-team-${USER}" --ignore-not-found
  oc delete project "terminal-${USER}" --ignore-not-found

  echo "Done with $USER"
  echo
done

# Delete the user distribution application
echo "=== Removing the user-distribution project ==="
oc delete project user-distribution --ignore-not-found

# Uninstall the Web Terminal operator
echo "=== Uninstalling OpenShift Web Terminal Operator ==="

# Delete the subscription
oc delete subscription web-terminal -n openshift-operators --ignore-not-found

# Delete the CSV (the installed operator)
CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep web-terminal || true)
if [ -n "$CSV" ]; then
  oc delete "$CSV" -n openshift-operators
  echo "Web Terminal operator removed."
else
  echo "No Web Terminal operator CSV found, skipping."
fi

# Remove the DevWorkspace custom resources used by the Operator, along with any related Kubernetes objects
oc delete devworkspaces.workspace.devfile.io --all-namespaces --all --wait
oc delete devworkspaceroutings.controller.devfile.io --all-namespaces --all --wait

oc delete subscription devworkspace-operator-fast-redhat-operators-openshift-marketplace -n openshift-operators
oc delete csv devworkspace-operator.v0.39.0 -n openshift-operators

# Remove the CRDs used by the Operator
oc delete customresourcedefinitions.apiextensions.k8s.io devworkspaceroutings.controller.devfile.io
oc delete customresourcedefinitions.apiextensions.k8s.io devworkspaces.workspace.devfile.io
oc delete customresourcedefinitions.apiextensions.k8s.io devworkspacetemplates.workspace.devfile.io
oc delete customresourcedefinitions.apiextensions.k8s.io devworkspaceoperatorconfigs.controller.devfile.io

# Remove the devworkspace-webhook-server deployment, mutating, and validating webhooks
oc delete deployment/devworkspace-webhook-server -n openshift-operators
oc delete mutatingwebhookconfigurations controller.devfile.io
oc delete validatingwebhookconfigurations controller.devfile.io

# Remove any remaining services, secrets, and config maps
oc delete all --selector app.kubernetes.io/part-of=devworkspace-operator,app.kubernetes.io/name=devworkspace-webhook-server -n openshift-operators
oc delete serviceaccounts devworkspace-webhook-server -n openshift-operators
oc delete clusterrole devworkspace-webhook-server
oc delete clusterrolebinding devworkspace-webhook-server


echo
echo "============================================"
echo "Cluster cleanup complete!"
echo "Removed projects for $NUM_USERS user(s)."
echo "Web Terminal operator has been uninstalled."
echo "============================================"
