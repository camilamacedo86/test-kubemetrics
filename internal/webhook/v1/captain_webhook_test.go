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
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/ptr"

	crewv1 "github.com/camilamacedo86/test-kubemetrics/api/v1"
	crewv2 "github.com/camilamacedo86/test-kubemetrics/api/v2"
	// TODO (user): Add any additional imports if needed
)

var _ = Describe("Captain Webhook", func() {
	var (
		obj       *crewv1.Captain
		oldObj    *crewv1.Captain
		validator CaptainValidator
		defaulter CaptainDefaulter
	)

	BeforeEach(func() {
		obj = &crewv1.Captain{}
		oldObj = &crewv1.Captain{}
		validator = CaptainValidator{}
		Expect(validator).NotTo(BeNil(), "Expected validator to be initialized")
		defaulter = CaptainDefaulter{}
		Expect(defaulter).NotTo(BeNil(), "Expected defaulter to be initialized")
		Expect(oldObj).NotTo(BeNil(), "Expected oldObj to be initialized")
		Expect(obj).NotTo(BeNil(), "Expected obj to be initialized")
	})

	AfterEach(func() {
		// TODO (user): Add any teardown logic common to all tests
	})

	// ADD:TO MAKE WORK - tests of the implementation of the webhooks.
	Context("When creating Captain under Defaulting Webhook", func() {
		It("Should apply defaults when the fields are empty", func() {
			Expect(defaulter.Default(ctx, obj)).To(Succeed())
			Expect(obj.Spec.Replicas).To(HaveValue(Equal(DefaultReplicas)))
			Expect(obj.Spec.Rank).To(Equal(DefaultRank))
		})

		It("Should not overwrite the fields which are set", func() {
			obj.Spec.Replicas = ptr.To[int32](3)
			obj.Spec.Rank = "Admiral"
			Expect(defaulter.Default(ctx, obj)).To(Succeed())
			Expect(obj.Spec.Replicas).To(HaveValue(Equal(int32(3))))
			Expect(obj.Spec.Rank).To(Equal("Admiral"))
		})
	})

	Context("When creating or updating Captain under Validating Webhook", func() {
		It("Should deny creation and update if the value is out of range", func() {
			obj.Spec.Replicas = ptr.To[int32](10)
			Expect(validator.ValidateCreate(ctx, obj)).Error().To(HaveOccurred())
			Expect(validator.ValidateUpdate(ctx, oldObj, obj)).Error().To(HaveOccurred())
		})

		It("Should admit creation and update if the value is in range", func() {
			obj.Spec.Replicas = ptr.To[int32](5)
			Expect(validator.ValidateCreate(ctx, obj)).Error().NotTo(HaveOccurred())
			Expect(validator.ValidateUpdate(ctx, oldObj, obj)).Error().NotTo(HaveOccurred())
		})
	})

	Context("When creating Captain under Conversion Webhook", func() {
		It("Should convert the object from the spoke (v2) to the hub (v1) and back", func() {
			spoke := &crewv2.Captain{
				ObjectMeta: metav1.ObjectMeta{Name: "captain", Namespace: "default"},
				Spec:       crewv2.CaptainSpec{Size: ptr.To[int32](3), Rank: "Admiral", Tags: []string{"brave"}},
				Status:     crewv2.CaptainStatus{Phase: "Ready", ReadySize: ptr.To[int32](2)},
			}

			hub := &crewv1.Captain{}
			Expect(spoke.ConvertTo(hub)).To(Succeed())
			Expect(hub.Name).To(Equal("captain"))
			Expect(hub.Spec.Replicas).To(HaveValue(Equal(int32(3))))
			Expect(hub.Spec.Rank).To(Equal("Admiral"))
			Expect(hub.Spec.Tags).To(Equal([]string{"brave"}))
			Expect(hub.Status.Phase).To(Equal("Ready"))
			Expect(hub.Status.ReadyReplicas).To(HaveValue(Equal(int32(2))))

			converted := &crewv2.Captain{}
			Expect(converted.ConvertFrom(hub)).To(Succeed())
			Expect(converted).To(Equal(spoke))
		})
	})
})
