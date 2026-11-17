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

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// ADD:TO MAKE WORK - the fields of the spec and status replace the example field "foo" of the scaffold.

// CaptainSpec defines the desired state of Captain
type CaptainSpec struct {
	// ADD:TO MAKE WORK - "+k8s:controller-gen:metrics:gauge" on a field: gauge with the value of the field.

	// replicas is the desired number of crew members. Defaulted to 1 by the defaulting webhook.
	// +k8s:controller-gen:metrics:gauge:name="spec_replicas",help="The desired number of crew members."
	// +optional
	Replicas *int32 `json:"replicas,omitempty"`

	// rank is the rank of the captain. Defaulted to "Commander" by the defaulting webhook.
	// +kubebuilder:validation:Enum=Commander;Admiral
	// +optional
	Rank string `json:"rank,omitempty"`

	// ADD:TO MAKE WORK - "+k8s:controller-gen:metrics:info" on a list: one info metric per element.

	// tags are free-form tags of the captain.
	// +k8s:controller-gen:metrics:info:name="tags",help="The tags of a captain.",labels={tag:"."}
	// +listType=set
	// +optional
	Tags []string `json:"tags,omitempty"`
}

// CaptainStatus defines the observed state of Captain.
type CaptainStatus struct {
	// ADD:TO MAKE WORK - "+k8s:controller-gen:metrics:stateset": one metric per state, 1 for the current one.

	// phase is the current phase of the captain.
	// +k8s:controller-gen:metrics:stateset:name="status_phase",help="The phase of a captain.",states={"Pending","Ready","Failed"},labelName="phase"
	// +optional
	Phase string `json:"phase,omitempty"`

	// ADD:TO MAKE WORK - gauge with missingAsZero: 0 is exposed while the status is not set yet.

	// readyReplicas is the number of ready crew members.
	// +k8s:controller-gen:metrics:gauge:name="status_ready_replicas",help="The number of ready crew members.",missingAsZero=true
	// +optional
	ReadyReplicas *int32 `json:"readyReplicas,omitempty"`

	// ADD:TO MAKE WORK - stateset and gauge on a list of objects: "value" selects the field of each
	// element, "labels" adds labels with the values of fields of each element.

	// conditions represent the current state of the Captain resource.
	// +k8s:controller-gen:metrics:stateset:name="status_condition",help="The condition of a captain.",states={"True","False","Unknown"},labelName="status",value=".status",labels={"type":".type"}
	// +k8s:controller-gen:metrics:gauge:name="status_condition_last_transition_time",help="The condition last transition time of a captain.",value=".lastTransitionTime",labels={"type":".type","status":".status"}
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// ADD:TO MAKE WORK - the "+k8s:controller-gen:metrics" markers below:
// - store: enables the generation of the state metrics configuration for this type. It is only set on v1
//   (the hub and storage version), not on v2, otherwise every Captain is exposed once per version.
// - label: labels added to all the metrics of the Captain.
// - gauge on the type: metric with a path relative to the Captain.

// +kubebuilder:object:root=true
// +kubebuilder:storageversion
// +kubebuilder:subresource:status
// +k8s:controller-gen:metrics:store:namePrefix="captain"
// +k8s:controller-gen:metrics:label:name="rank",value=".spec.rank"
// +k8s:controller-gen:metrics:label:name="exported_namespace",value=".metadata.namespace"
// +k8s:controller-gen:metrics:gauge:name="created",help="Unix creation timestamp.",path=".metadata.creationTimestamp"

// Captain is the Schema for the captains API
type Captain struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Captain
	// +required
	Spec CaptainSpec `json:"spec"`

	// status defines the observed state of Captain
	// +optional
	Status CaptainStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// CaptainList contains a list of Captain
type CaptainList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Captain `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &Captain{}, &CaptainList{})
		return nil
	})
}
