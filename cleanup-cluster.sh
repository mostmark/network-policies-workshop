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

echo
echo "============================================"
echo "Cluster cleanup complete!"
echo "Removed projects for $NUM_USERS user(s)."
echo "Web Terminal operator has been uninstalled."
echo "============================================"
