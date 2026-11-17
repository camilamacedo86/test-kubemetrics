# test-kubemetrics

<!-- ADD:TO MAKE WORK - this section is not scaffolded by Kubebuilder. -->
**POC:** a project scaffolded with Kubebuilder (master) to verify that the `state-metrics-config` generator
of controller-gen, proposed in [controller-tools#1043](https://github.com/kubernetes-sigs/controller-tools/pull/1043),
works with the Kubebuilder scaffold.

- The API `Captain` has two versions (`v1` hub and storage version, `v2` spoke) with defaulting, validation
  and conversion webhooks, all scaffolded with `kubebuilder create api` and `kubebuilder create webhook`.
- The `+k8s:controller-gen:metrics` markers are set on [api/v1/captain_types.go](api/v1/captain_types.go).
- `make manifests` generates the kube-state-metrics configuration and its ClusterRole into
  [config/state-metrics/bases](config/state-metrics/bases). controller-gen is built from the pull request.
- [config/state-metrics](config/state-metrics) deploys kube-state-metrics with that configuration. It is added
  to [config/default](config/default/kustomization.yaml).
- Everything added on top of the scaffold is marked with `ADD:TO MAKE WORK`:
  `grep -rn "ADD:TO MAKE WORK" --exclude-dir=bin --exclude-dir=dist .`

| What | How | Verified by |
|---|---|---|
| Default scaffold + state metrics | `make deploy` | `make test-e2e` |
| All options of the scaffold (Prometheus, NetworkPolicies, metrics certificates) + state metrics | `hack/all-options.sh enable` and `make deploy` | `make test-e2e-all-options` |
| Helm chart (generated with all options, `make helm-chart`) | `make helm-deploy` | `make test-e2e-helm` |

The three e2e profiles run in the [E2E Tests](.github/workflows/test-e2e.yml) workflow.

// TODO(user): Add simple overview of use/purpose

## Description
// TODO(user): An in-depth paragraph about your project and overview of use

## Getting Started

### Prerequisites
- go version v1.24.6+
- docker version 17.03+.
- kubectl version v1.11.3+.
- Access to a Kubernetes v1.11.3+ cluster.

### To Deploy on the cluster
**Build and push your image to the location specified by `IMG`:**

```sh
make docker-build docker-push IMG=<some-registry>/test-kubemetrics:tag
```

**NOTE:** This image ought to be published in the personal registry you specified.
And it is required to have access to pull the image from the working environment.
Make sure you have the proper permission to the registry if the above commands don’t work.

**Install the CRDs into the cluster:**

```sh
make install
```

**Deploy the Manager to the cluster with the image specified by `IMG`:**

```sh
make deploy IMG=<some-registry>/test-kubemetrics:tag
```

> **NOTE**: If you encounter RBAC errors, you may need to grant yourself cluster-admin
privileges or be logged in as admin.

**Create instances of your solution**
You can apply the samples (examples) from the config/sample:

```sh
kubectl apply -k config/samples/
```

>**NOTE**: Ensure that the samples has default values to test it out.

### To Uninstall
**Delete the instances (CRs) from the cluster:**

```sh
kubectl delete -k config/samples/
```

**Delete the APIs(CRDs) from the cluster:**

```sh
make uninstall
```

**UnDeploy the controller from the cluster:**

```sh
make undeploy
```

## Project Distribution

Following the options to release and provide this solution to the users.

### By providing a bundle with all YAML files

1. Build the installer for the image built and published in the registry:

```sh
make build-installer IMG=<some-registry>/test-kubemetrics:tag
```

**NOTE:** The makefile target mentioned above generates an 'install.yaml'
file in the dist directory. This file contains all the resources built
with Kustomize, which are necessary to install this project without its
dependencies.

2. Using the installer

Users can just run 'kubectl apply -f <URL for YAML BUNDLE>' to install
the project, i.e.:

```sh
kubectl apply -f https://raw.githubusercontent.com/<org>/test-kubemetrics/<tag or branch>/dist/install.yaml
```

### By providing a Helm Chart

1. Build the chart using the optional helm plugin

```sh
kubebuilder edit --plugins=helm/v2-alpha
```

2. See that a chart was generated under 'dist/chart', and users
can obtain this solution from there.

**NOTE:** If you change the project, you need to update the Helm Chart
using the same command above to sync the latest changes. Furthermore,
if you create webhooks, you need to use the above command with
the '--force' flag and manually ensure that any custom configuration
previously added to 'dist/chart/values.yaml' or 'dist/chart/manager/manager.yaml'
is manually re-applied afterwards.

## Contributing
// TODO(user): Add detailed information on how you would like others to contribute to this project

**NOTE:** Run `make help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## License

Copyright 2026 The Kubernetes authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

