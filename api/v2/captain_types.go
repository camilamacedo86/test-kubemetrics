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

package v2

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// ADD:TO MAKE WORK - the fields of the spec and status: v2 names spec.replicas and status.readyReplicas of
// v1 as spec.size and status.readySize, to have a conversion which is not a plain copy.

// CaptainSpec defines the desired state of Captain
type CaptainSpec struct {
	// size is the desired number of crew members. It is named replicas in v1.
	// +optional
	Size *int32 `json:"size,omitempty"`

	// rank is the rank of the captain.
	// +kubebuilder:validation:Enum=Commander;Admiral
	// +optional
	Rank string `json:"rank,omitempty"`

	// tags are free-form tags of the captain.
	// +listType=set
	// +optional
	Tags []string `json:"tags,omitempty"`
}

// CaptainStatus defines the observed state of Captain.
type CaptainStatus struct {
	// phase is the current phase of the captain.
	// +optional
	Phase string `json:"phase,omitempty"`

	// readySize is the number of ready crew members. It is named readyReplicas in v1.
	// +optional
	ReadySize *int32 `json:"readySize,omitempty"`

	// conditions represent the current state of the Captain resource.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// ADD:TO MAKE WORK - v2 intentionally has no "+k8s:controller-gen:metrics" markers: the metrics are
// generated for the hub and storage version (v1) only. kube-state-metrics reads the Captains as v1,
// so the Captains created as v2 are exposed too.

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

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
