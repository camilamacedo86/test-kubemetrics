#!/usr/bin/env bash

# ADD:TO MAKE WORK - this script is not scaffolded by Kubebuilder.
#
# The Helm plugin of Kubebuilder (helm.kubebuilder.io/v2-alpha) generates dist/chart from the kustomize
# output. It is written for the resources of the Kubebuilder scaffold and mishandles the additional
# resources of config/state-metrics (kube-state-metrics). This script is run by "make helm-chart" after
# the generation and fixes the chart. Every fix fails if the generated chart doesn't look as expected,
# so that the script is revisited when the plugin changes.

set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CHART=dist/chart
PROJECT_NAME=test-kubemetrics

# edit <file> <perl substitution>: applies the substitution to the whole file, fails if nothing matched.
function edit {
  local file=$1 expr=$2
  perl -0pi -e "\$c += ${expr}; END { exit(\$c ? 0 : 1) }" "${file}" || {
    echo "ERROR: nothing to change in ${file} for: ${expr}" >&2
    exit 1
  }
}

# 1. The plugin keeps only one ServiceAccount of the kustomize output (the last one). The ServiceAccount of
#    the manager is dropped, while the manager Deployment still uses it: the manager pod can't be created.
#    Add the template the plugin generates for a project without a second ServiceAccount.
manager_sa="${CHART}/templates/rbac/controller-manager.yaml"
if [[ -f "${manager_sa}" ]]; then
  echo "ERROR: ${manager_sa} exists, the Helm plugin seems to handle multiple ServiceAccounts now" >&2
  exit 1
fi
cat > "${manager_sa}" <<TEMPLATE
{{- if .Values.serviceAccount.enabled }}
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    app.kubernetes.io/name: {{ include "${PROJECT_NAME}.name" . }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    {{- with .Values.serviceAccount.labels }}
    {{- with omit . "app.kubernetes.io/managed-by" "app.kubernetes.io/name" "helm.sh/chart" "app.kubernetes.io/instance" }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  name: {{ include "${PROJECT_NAME}.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
{{- end }}
TEMPLATE

# 2. The ServiceAccount of kube-state-metrics is generated as if it were the one of the manager: it is only
#    installed with serviceAccount.enabled, gets the labels and annotations of serviceAccount.* and its name
#    is not templated, while the Deployment and the bindings use the templated name. They only match if the
#    release is named after the chart.
grep -q "^  name: ${PROJECT_NAME}-state-metrics$" "${CHART}/templates/rbac/state-metrics.yaml" || {
  echo "ERROR: ${CHART}/templates/rbac/state-metrics.yaml doesn't have the expected hard-coded name" >&2
  exit 1
}
cat > "${CHART}/templates/rbac/state-metrics.yaml" <<TEMPLATE
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    app.kubernetes.io/name: {{ include "${PROJECT_NAME}.name" . }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
    app.kubernetes.io/instance: {{ .Release.Name }}
  name: {{ include "${PROJECT_NAME}.resourceName" (dict "suffix" "state-metrics" "context" \$) }}
  namespace: {{ .Release.Namespace }}
TEMPLATE

# 3. The Service of kube-state-metrics is handled as the metrics Service of the manager, as its name
#    contains "metrics": the port 8080 is replaced by metrics.port (8443) and the Service is only installed
#    with metrics.enabled.
service="${CHART}/templates/metrics/state-metrics-service.yaml"
edit "${service}" 's/port: \{\{ \.Values\.metrics\.port \}\}/port: 8080/'
edit "${service}" 's/\A\{\{- if \.Values\.metrics\.enabled \}\}\n//'
edit "${service}" 's/\{\{- end \}\}\n?\z//'

# 4. For the same reason the ServiceMonitor of kube-state-metrics is only installed with metrics.enabled,
#    which is the setting for the metrics of the manager.
edit "${CHART}/templates/prometheus/state-metrics-monitor.yaml" \
  's/\{\{- if and \.Values\.prometheus\.enabled \.Values\.metrics\.enabled \}\}/{{- if .Values.prometheus.enabled }}/'

# 5. The ClusterRoles and ClusterRoleBindings of kube-state-metrics are turned into Roles and RoleBindings
#    with rbac.namespaced, like the ones of the manager. kube-state-metrics has to list the
#    CustomResourceDefinitions, which are cluster-scoped, and watches the custom resources of all namespaces.
for file in state-metrics-role state-metrics-rolebinding state-metrics-crd-reader-role state-metrics-crd-reader-rolebinding; do
  path="${CHART}/templates/rbac/${file}.yaml"
  edit "${path}" 's/\{\{- if \.Values\.rbac\.namespaced \}\}\nkind: (?:Role|RoleBinding)\n\{\{- else \}\}\n(kind: \w+\n)\{\{- end \}\}\n/$1/'
  edit "${path}" 's/\{\{- if \.Values\.rbac\.namespaced \}\}\n  namespace: \{\{ \.Release\.Namespace \}\}\n\{\{- end \}\}\n//'
done
for file in state-metrics-rolebinding state-metrics-crd-reader-rolebinding; do
  edit "${CHART}/templates/rbac/${file}.yaml" \
    's/  \{\{- if \.Values\.rbac\.namespaced \}\}\n  kind: Role\n  \{\{- else \}\}\n(  kind: ClusterRole\n)  \{\{- end \}\}\n/$1/'
done

echo "Fixed the Helm chart in ${CHART}"
