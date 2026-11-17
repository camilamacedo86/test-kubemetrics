# Image URL to use all building/pushing image targets
IMG ?= controller:latest
# YEAR defines the year value used for substituting the YEAR placeholder in the boilerplate header.
YEAR ?= $(shell date +%Y)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

# ADD:TO MAKE WORK - the second controller-gen call of the manifests target generates the kube-state-metrics
# configuration (metrics.yaml) and the ClusterRole (rbac.yaml) from the "+k8s:controller-gen:metrics" markers
# into config/state-metrics/bases.
.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole, CustomResourceDefinition and state metrics configuration objects.
	"$(CONTROLLER_GEN)" rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	"$(CONTROLLER_GEN)" state-metrics-config:experimental=true,target=$(STATE_METRICS_TARGET),roleName=state-metrics-role paths="./..." output:state-metrics-config:dir=config/state-metrics/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	"$(CONTROLLER_GEN)" object:headerFile="hack/boilerplate.go.txt",year=$(YEAR) paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet setup-envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell "$(ENVTEST)" use $(ENVTEST_K8S_VERSION) --bin-dir "$(LOCALBIN)" -p path)" go test $$(go list ./... | grep -v /e2e) -coverprofile cover.out

# TODO(user): To use a different vendor for e2e tests, modify the setup under 'tests/e2e'.
# The default setup assumes Kind is pre-installed and builds/loads the Manager Docker image locally.
# kubectl kuberc is disabled by default for test isolation; enable with:
# - KUBECTL_KUBERC=true
# CertManager is installed by default; skip with:
# - CERT_MANAGER_INSTALL_SKIP=true
KIND_CLUSTER ?= test-kubemetrics-test-e2e

.PHONY: setup-test-e2e
setup-test-e2e: kind ## Set up a Kind cluster for e2e tests if it does not exist
	@case "$$($(KIND) get clusters)" in \
		*"$(KIND_CLUSTER)"*) \
			echo "Kind cluster '$(KIND_CLUSTER)' already exists. Skipping creation." ;; \
		*) \
			echo "Creating Kind cluster '$(KIND_CLUSTER)'..."; \
			$(KIND) create cluster --name $(KIND_CLUSTER) ;; \
	esac

# ADD:TO MAKE WORK - E2E_PROFILE and the timeout are added to the scaffolded test-e2e target.
# test-e2e runs with the default scaffold of config/default (profile "default").
.PHONY: test-e2e
test-e2e: setup-test-e2e manifests generate fmt vet ## Run the e2e tests. Expected an isolated environment using Kind.
	KIND=$(KIND) KIND_CLUSTER=$(KIND_CLUSTER) E2E_PROFILE=$(E2E_PROFILE) go test -tags=e2e ./test/e2e/ -v -ginkgo.v -timeout 30m
	$(MAKE) cleanup-test-e2e

# ADD:TO MAKE WORK - the targets below are not scaffolded by Kubebuilder.
# E2E_PROFILE selects what the e2e tests deploy and verify:
# - default: the default scaffold of config/default with kustomize
# - all-options: config/default with all options enabled by hack/all-options.sh with kustomize
# - helm: the Helm chart of dist/chart, which is generated with all options enabled
E2E_PROFILE ?= default

.PHONY: test-e2e-all-options
test-e2e-all-options: ## Run the e2e tests with all the options of the kustomize scaffold enabled.
	hack/all-options.sh enable
	rc=0; $(MAKE) test-e2e E2E_PROFILE=all-options || rc=$$?; hack/all-options.sh restore; exit $$rc

.PHONY: test-e2e-helm
test-e2e-helm: helm ## Run the e2e tests installing the project with the Helm chart.
	$(MAKE) test-e2e E2E_PROFILE=helm

# The chart is generated with all the options of the kustomize scaffold enabled and then fixed, see
# hack/helm-chart-fixups.sh.
.PHONY: helm-chart
helm-chart: manifests generate kustomize ## Regenerate the Helm chart (dist/chart) with all options enabled. Requires kubebuilder.
	@command -v kubebuilder >/dev/null || { echo "kubebuilder is required to generate the Helm chart"; exit 1; }
	hack/all-options.sh enable
	rm -rf $(HELM_CHART_DIR)/templates
	rc=0; kubebuilder edit --plugins=helm.kubebuilder.io/v2-alpha || rc=$$?; hack/all-options.sh restore; exit $$rc
	hack/helm-chart-fixups.sh

# The Helm chart can only be regenerated with kubebuilder ("make helm-chart"). This verifies without it that
# the state metrics configuration of the chart is the one generated by controller-gen.
.PHONY: verify-helm-chart
verify-helm-chart: manifests ## Verify that the state metrics configuration of the Helm chart is up to date.
	@count=$$(ls $(HELM_CHART_DIR)/templates/extras/state-metrics-config-*.yaml | wc -l); \
	[ "$$count" -eq 1 ] || { echo "Expected one state-metrics-config ConfigMap in the Helm chart, found $$count: run make helm-chart"; exit 1; }
	@sed 's/^/    /' config/state-metrics/bases/metrics.yaml > "$(LOCALBIN)/metrics-expected.yaml"; \
	awk '/^  metrics.yaml: \|/{f=1;next} /^[a-z]/{f=0} f' $(HELM_CHART_DIR)/templates/extras/state-metrics-config-*.yaml > "$(LOCALBIN)/metrics-chart.yaml"; \
	diff -u "$(LOCALBIN)/metrics-expected.yaml" "$(LOCALBIN)/metrics-chart.yaml" || { echo "The Helm chart is out of date, run: make helm-chart"; exit 1; }

.PHONY: verify-generated
verify-generated: manifests generate ## Verify that the generated files are up to date.
	@git diff --exit-code -- api config || { echo "Generated files are out of date, run: make manifests generate"; exit 1; }
	@[ -z "$$(git status --porcelain -- api config)" ] || { git status --porcelain -- api config; echo "Generated files are not committed"; exit 1; }

.PHONY: cleanup-test-e2e
cleanup-test-e2e: kind ## Tear down the Kind cluster used for e2e tests
	@$(KIND) delete cluster --name $(KIND_CLUSTER)

.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter
	"$(GOLANGCI_LINT)" run

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform fixes
	"$(GOLANGCI_LINT)" run --fix

.PHONY: lint-config
lint-config: golangci-lint ## Verify golangci-lint linter configuration
	"$(GOLANGCI_LINT)" config verify

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager cmd/main.go

.PHONY: run
# Use RUN_ARGS to pass arguments to the manager, e.g. RUN_ARGS="--webhook-port=-1".
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go $(RUN_ARGS)

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# Override BASE_IMAGE to build from another registry, e.g.
# make docker-build IMG=<img> BASE_IMAGE=docker.io/library/golang:1.26
.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build $(if $(BASE_IMAGE),--build-arg BASE_IMAGE=$(BASE_IMAGE)) -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name test-kubemetrics-builder
	$(CONTAINER_TOOL) buildx use test-kubemetrics-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) $(if $(BASE_IMAGE),--build-arg BASE_IMAGE=$(BASE_IMAGE)) --tag ${IMG} -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm test-kubemetrics-builder
	rm Dockerfile.cross

.PHONY: build-installer
build-installer: manifests generate kustomize ## Generate a consolidated YAML with CRDs and deployment.
	mkdir -p dist
	cd config/manager && "$(KUSTOMIZE)" edit set image controller=${IMG}
	"$(KUSTOMIZE)" build config/default > dist/install.yaml

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	@out="$$( "$(KUSTOMIZE)" build config/crd 2>/dev/null || true )"; \
	if [ -n "$$out" ]; then echo "$$out" | "$(KUBECTL)" apply -f -; else echo "No CRDs to install; skipping."; fi

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	@out="$$( "$(KUSTOMIZE)" build config/crd 2>/dev/null || true )"; \
	if [ -n "$$out" ]; then echo "$$out" | "$(KUBECTL)" delete --ignore-not-found=$(ignore-not-found) -f -; else echo "No CRDs to delete; skipping."; fi

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && "$(KUSTOMIZE)" edit set image controller=${IMG}
	"$(KUSTOMIZE)" build config/default | "$(KUBECTL)" apply -f -

.PHONY: undeploy
undeploy: kustomize ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	"$(KUSTOMIZE)" build config/default | "$(KUBECTL)" delete --ignore-not-found=$(ignore-not-found) -f -

##@ Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p "$(LOCALBIN)"

## Tool Binaries
KUBECTL ?= kubectl
KIND ?= $(LOCALBIN)/kind
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest
GOLANGCI_LINT = $(LOCALBIN)/golangci-lint

## Tool Versions
KUSTOMIZE_VERSION ?= v5.8.1
CONTROLLER_TOOLS_VERSION ?= v0.23.0
# ADD:TO MAKE WORK - The state-metrics-config generator is not released yet. controller-gen is therefore built from the
# pull request https://github.com/kubernetes-sigs/controller-tools/pull/1043 at the commit below.
# Set CONTROLLER_TOOLS_DIR to a local checkout of controller-tools to build from it instead.
CONTROLLER_TOOLS_REPO ?= https://github.com/kubernetes-sigs/controller-tools.git
CONTROLLER_TOOLS_PR ?= 1043
CONTROLLER_TOOLS_COMMIT ?= 461cc2474d75763a4072eb9361c8acccf98d4751
CONTROLLER_TOOLS_DIR ?=
# STATE_METRICS_TARGET is the target the state metrics configuration is generated for.
# config/state-metrics deploys kube-state-metrics, which is the only target wired up in this project.
STATE_METRICS_TARGET ?= kube-state-metrics

#ENVTEST_VERSION is the controller-runtime version to use for setup-envtest, derived from go.mod
ENVTEST_VERSION ?= $(shell v='$(call gomodver,sigs.k8s.io/controller-runtime)'; \
  [ -n "$$v" ] || { echo "Set ENVTEST_VERSION manually (controller-runtime replace has no tag)" >&2; exit 1; }; \
  printf '%s\n' "$$v")

#ENVTEST_K8S_VERSION is the version of Kubernetes to use for setting up ENVTEST binaries (i.e. 1.31)
ENVTEST_K8S_VERSION ?= $(shell v='$(call gomodver,k8s.io/api)'; \
  [ -n "$$v" ] || { echo "Set ENVTEST_K8S_VERSION manually (k8s.io/api replace has no tag)" >&2; exit 1; }; \
  printf '%s\n' "$$v" | sed -E 's/^v?[0-9]+\.([0-9]+).*/1.\1/')

GOLANGCI_LINT_VERSION ?= v2.15.0
KIND_VERSION ?= v0.33.0
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

.PHONY: controller-gen
controller-gen: ## Build controller-gen locally if necessary.
# ADD:TO MAKE WORK - the scaffold installs a released version with go-install-tool:
#	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen,$(CONTROLLER_TOOLS_VERSION))
# "go install sigs.k8s.io/controller-tools/cmd/controller-gen@<commit>" can't resolve the commit of a pull
# request, so the commit is fetched with git and built from source. The binary is kept per commit. With
# CONTROLLER_TOOLS_DIR it is always rebuilt from the local checkout.
CONTROLLER_GEN_BUILD = $(CONTROLLER_GEN)-$(if $(CONTROLLER_TOOLS_DIR),local,$(CONTROLLER_TOOLS_COMMIT))
controller-gen: $(LOCALBIN)
	@if [ -n "$(CONTROLLER_TOOLS_DIR)" ] || [ ! -f "$(CONTROLLER_GEN_BUILD)" ]; then \
	set -e; \
	src="$(CONTROLLER_TOOLS_DIR)"; \
	if [ -z "$$src" ]; then \
		src="$$(mktemp -d)"; trap 'rm -rf "$$src"' EXIT; \
		git -C "$$src" init -q; \
		echo "Fetching controller-tools PR #$(CONTROLLER_TOOLS_PR) ($(CONTROLLER_TOOLS_COMMIT))"; \
		git -C "$$src" fetch -q --depth 1 "$(CONTROLLER_TOOLS_REPO)" "$(CONTROLLER_TOOLS_COMMIT)"; \
		git -C "$$src" checkout -q FETCH_HEAD; \
	fi; \
	echo "Building controller-gen from $$src"; \
	(cd "$$src" && go build -o "$(CONTROLLER_GEN_BUILD)" ./cmd/controller-gen); \
	fi
	@ln -sf "$$(basename "$(CONTROLLER_GEN_BUILD)")" "$(CONTROLLER_GEN)"

.PHONY: setup-envtest
setup-envtest: envtest ## Download the binaries required for ENVTEST in the local bin directory.
	@echo "Setting up envtest binaries for Kubernetes version $(ENVTEST_K8S_VERSION)..."
	@"$(ENVTEST)" use $(ENVTEST_K8S_VERSION) --bin-dir "$(LOCALBIN)" -p path || { \
		echo "Error: Failed to set up envtest binaries for version $(ENVTEST_K8S_VERSION)."; \
		exit 1; \
	}

.PHONY: envtest
envtest: $(ENVTEST) ## Download setup-envtest locally if necessary.
$(ENVTEST): $(LOCALBIN)
	$(call go-install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest,$(ENVTEST_VERSION))

.PHONY: golangci-lint
golangci-lint: $(GOLANGCI_LINT) ## Download golangci-lint locally if necessary.
$(GOLANGCI_LINT): $(LOCALBIN)
	$(call go-install-tool,$(GOLANGCI_LINT),github.com/golangci/golangci-lint/v2/cmd/golangci-lint,$(GOLANGCI_LINT_VERSION))
	@test -f .custom-gcl.yml && { \
		echo "Building custom golangci-lint with plugins..." && \
		$(GOLANGCI_LINT) custom --destination $(LOCALBIN) --name golangci-lint-custom && \
		mv -f $(LOCALBIN)/golangci-lint-custom $(GOLANGCI_LINT); \
	} || true

.PHONY: kind
kind: $(LOCALBIN) ## Download kind locally if necessary.
ifeq ($(KIND),$(LOCALBIN)/kind)
	$(call go-install-tool,$(KIND),sigs.k8s.io/kind,$(KIND_VERSION))
endif

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] && [ "$$(readlink -- "$(1)" 2>/dev/null)" = "$(1)-$(3)" ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
rm -f "$(1)" ;\
GOBIN="$(LOCALBIN)" go install $${package} ;\
mv "$(LOCALBIN)/$$(basename "$(1)")" "$(1)-$(3)" ;\
} ;\
ln -sf "$$(realpath "$(1)-$(3)")" "$(1)"
endef

define gomodver
$(shell go list -m -f '{{if .Replace}}{{.Replace.Version}}{{else}}{{.Version}}{{end}}' $(1) 2>/dev/null)
endef

##@ Helm Deployment

## Helm binary to use for deploying the chart
HELM ?= $(LOCALBIN)/helm
## Helm version to install
HELM_VERSION ?= v4.3.1
## Namespace to deploy the Helm release
HELM_NAMESPACE ?= test-kubemetrics-system
## Name of the Helm release
HELM_RELEASE ?= test-kubemetrics
## Path to the Helm chart directory
HELM_CHART_DIR ?= dist/chart
## Additional arguments to pass to helm commands
HELM_EXTRA_ARGS ?=

.PHONY: helm
helm: $(LOCALBIN) ## Download Helm locally if necessary.
ifeq ($(HELM),$(LOCALBIN)/helm)
helm: $(LOCALBIN)/helm-$(HELM_VERSION)
	@ln -sf "helm-$(HELM_VERSION)" "$(HELM)"
endif

# The Helm install script checks that helm is on PATH
$(LOCALBIN)/helm-$(HELM_VERSION): | $(LOCALBIN)
	curl -fsSL -o "$(LOCALBIN)/get-helm-4" https://raw.githubusercontent.com/helm/helm/$(HELM_VERSION)/scripts/get-helm-4
	PATH="$(LOCALBIN):$$PATH" HELM_INSTALL_DIR="$(LOCALBIN)" BINARY_NAME=helm-$(HELM_VERSION) USE_SUDO=false \
		bash "$(LOCALBIN)/get-helm-4" --version $(HELM_VERSION)

.PHONY: helm-deploy
helm-deploy: helm ## Deploy manager to the K8s cluster via Helm. Specify an image with IMG.
	IMG="$(IMG)"; $(HELM) upgrade --install $(HELM_RELEASE) $(HELM_CHART_DIR) \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace \
		--set manager.image.repository=$${IMG%:*} \
		--set manager.image.tag=$${IMG##*:} \
		--wait \
		--timeout 5m \
		$(HELM_EXTRA_ARGS)

.PHONY: helm-uninstall
helm-uninstall: helm ## Uninstall the Helm release from the K8s cluster.
	$(HELM) uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

.PHONY: helm-status
helm-status: helm ## Show Helm release status.
	$(HELM) status $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

.PHONY: helm-history
helm-history: helm ## Show Helm release history.
	$(HELM) history $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

.PHONY: helm-rollback
helm-rollback: helm ## Rollback to previous Helm release.
	$(HELM) rollback $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)
