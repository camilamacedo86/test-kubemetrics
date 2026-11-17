#!/usr/bin/env bash

# ADD:TO MAKE WORK - this script is not scaffolded by Kubebuilder.
#
# The scaffold of Kubebuilder ships several options commented out in the kustomize configuration
# (the [PROMETHEUS], [METRICS-WITH-CERTS], [PROMETHEUS-WITH-CERTS] and [NETWORK POLICY] sections).
# config/default is kept as the default scaffold plus config/state-metrics. This script enables ALL
# the options on top of it, so that the e2e tests and the Helm chart can verify that the state metrics
# also work with all of them:
#
#   hack/all-options.sh enable    enables all options (a backup of the changed files is kept in bin/)
#   hack/all-options.sh restore   restores the files from the backup
#
# Webhooks and cert-manager ([WEBHOOK] and [CERTMANAGER]) are already enabled by
# "kubebuilder create webhook".

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BACKUP_DIR=bin/all-options-backup
FILES=(
  config/default/kustomization.yaml
  config/prometheus/kustomization.yaml
  config/state-metrics/kustomization.yaml
)

# edit <file> <perl substitution>: applies the substitution to the whole file, fails if nothing matched.
function edit {
  local file=$1 expr=$2
  perl -0pi -e "\$c += ${expr}; END { exit(\$c ? 0 : 1) }" "${file}" || {
    echo "ERROR: nothing to change in ${file} for: ${expr}" >&2
    exit 1
  }
}

function enable {
  if [[ -d "${BACKUP_DIR}" ]]; then
    echo "All options are already enabled (${BACKUP_DIR} exists). Run '$0 restore' first." >&2
    exit 1
  fi
  for file in "${FILES[@]}"; do
    mkdir -p "${BACKUP_DIR}/$(dirname "${file}")"
    cp "${file}" "${BACKUP_DIR}/${file}"
  done

  # Restore the files if one of the changes below fails, to not leave them partially changed.
  trap 'restore' ERR

  local default=config/default/kustomization.yaml
  # [PROMETHEUS] ServiceMonitor of the controller manager metrics.
  edit "${default}" 's{^#- \.\./prometheus$}{- ../prometheus}m'
  # [NETWORK POLICY] Restrict the ingress to the metrics and webhook ports of the controller manager.
  edit "${default}" 's{^#- \.\./network-policy$}{- ../network-policy}m'
  # [METRICS-WITH-CERTS] Serve the controller manager metrics with a certificate of cert-manager.
  edit "${default}" 's{^#(- path: cert_metrics_manager_patch\.yaml)\n#(  target:)\n#(    kind: Deployment)\n#(    name: controller-manager)$}{$1\n$2\n$3\n$4}m'
  # [METRICS-WITH-CERTS] and [PROMETHEUS-WITH-CERTS] replacements for the metrics certificate.
  edit "${default}" 's{(^# - source: # Uncomment the following block to enable certificates for metrics.*?)(?=^ - source: # Uncomment the following block if you have any webhook)}{ (my $b = $1) =~ s/^#//mg; $b }mse'

  # [PROMETHEUS-WITH-CERTS] Let the ServiceMonitor of the controller manager use the metrics certificate.
  edit config/prometheus/kustomization.yaml 's{^#(patches:)\n#(  - path: monitor_tls_patch\.yaml)\n#(    target:)\n#(      kind: ServiceMonitor)$}{$1\n$2\n$3\n$4}m'

  # [PROMETHEUS] ServiceMonitor of the custom resource state metrics (kube-state-metrics).
  edit config/state-metrics/kustomization.yaml 's{^#- monitor\.yaml$}{- monitor.yaml}m'

  echo "All options enabled in: ${FILES[*]}"
}

function restore {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    echo "Nothing to restore (${BACKUP_DIR} does not exist)."
    return
  fi
  for file in "${FILES[@]}"; do
    cp "${BACKUP_DIR}/${file}" "${file}"
  done
  rm -rf "${BACKUP_DIR}"
  echo "Restored: ${FILES[*]}"
}

case "${1:-}" in
  enable) enable ;;
  restore) restore ;;
  *)
    echo "Usage: $0 enable|restore" >&2
    exit 1
    ;;
esac
