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
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"k8s.io/utils/ptr"

	crewv2 "github.com/camilamacedo86/test-kubemetrics/api/v2"
	// TODO (user): Add any additional imports if needed
)

var _ = Describe("Captain Webhook", func() {
	var (
		obj       *crewv2.Captain
		oldObj    *crewv2.Captain
		validator CaptainValidator
		defaulter CaptainDefaulter
	)

	BeforeEach(func() {
		obj = &crewv2.Captain{}
		oldObj = &crewv2.Captain{}
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
			Expect(obj.Spec.Size).To(HaveValue(Equal(DefaultSize)))
			Expect(obj.Spec.Rank).To(Equal(DefaultRank))
		})

		It("Should not overwrite the fields which are set", func() {
			obj.Spec.Size = ptr.To[int32](3)
			obj.Spec.Rank = "Admiral"
			Expect(defaulter.Default(ctx, obj)).To(Succeed())
			Expect(obj.Spec.Size).To(HaveValue(Equal(int32(3))))
			Expect(obj.Spec.Rank).To(Equal("Admiral"))
		})
	})

	Context("When creating or updating Captain under Validating Webhook", func() {
		It("Should deny creation and update if the value is out of range", func() {
			obj.Spec.Size = ptr.To[int32](10)
			Expect(validator.ValidateCreate(ctx, obj)).Error().To(HaveOccurred())
			Expect(validator.ValidateUpdate(ctx, oldObj, obj)).Error().To(HaveOccurred())
		})

		It("Should admit creation and update if the value is in range", func() {
			obj.Spec.Size = ptr.To[int32](5)
			Expect(validator.ValidateCreate(ctx, obj)).Error().NotTo(HaveOccurred())
			Expect(validator.ValidateUpdate(ctx, oldObj, obj)).Error().NotTo(HaveOccurred())
		})
	})
})
