/*
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
*/

package controller

import (
	"context"

	"k8s.io/apimachinery/pkg/api/equality"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	crewv1 "github.com/camilamacedo86/test-kubemetrics/api/v1"
)

// PausedAnnotation is the annotation to stop the reconciliation of a Captain when set to "true".
const PausedAnnotation = "crew.example.com/paused"

// CaptainReconciler reconciles a Captain object
type CaptainReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=crew.example.com,resources=captains,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=crew.example.com,resources=captains/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=crew.example.com,resources=captains/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the Captain object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.25.2/pkg/reconcile
func (r *CaptainReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	captain := &crewv1.Captain{}
	if err := r.Get(ctx, req.NamespacedName, captain); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// ADD:TO MAKE WORK - implementation of the controller, so that the status based metrics have values.
	// A Captain with the paused annotation is not reconciled: its status stays empty, which is used to
	// verify the metrics of a Captain without status (e.g. the gauge with missingAsZero).
	if captain.Annotations[PausedAnnotation] == "true" {
		return ctrl.Result{}, nil
	}

	// There is no real workload behind a Captain: the desired state is reported as observed state,
	// so that the status based metrics have values to expose.
	base := captain.DeepCopy()
	captain.Status.Phase = "Ready"
	captain.Status.ReadyReplicas = captain.Spec.Replicas
	meta.SetStatusCondition(&captain.Status.Conditions, metav1.Condition{
		Type:               "Available",
		Status:             metav1.ConditionTrue,
		Reason:             "CrewReady",
		Message:            "All crew members are ready",
		ObservedGeneration: captain.Generation,
	})
	if equality.Semantic.DeepEqual(base.Status, captain.Status) {
		return ctrl.Result{}, nil
	}
	if err := r.Status().Patch(ctx, captain, client.MergeFrom(base)); err != nil {
		return ctrl.Result{}, err
	}
	log.Info("Updated status", "phase", captain.Status.Phase)

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *CaptainReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&crewv1.Captain{}).
		Named("captain").
		Complete(r)
}
