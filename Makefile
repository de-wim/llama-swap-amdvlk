# Uncomment and edit to build experimental versions
#LLAMA_CPP_REPO = https://github.com/pwilkin/llama.cpp
#LLAMA_CPP_VERSION = autoparser
IMAGE_TAG_SUFFIX = 

LLAMA_SWAP_VERSION = v189
LLAMA_CPP_REPO ?= https://github.com/ggml-org/llama.cpp
LLAMA_CPP_VERSION ?= master
# Add PR numbers for unmerged PRs to include in this build here
LLAMA_CPP_INCLUDE_PRS=
IKLLAMA_CPP_REPO ?= https://github.com/ikawrakow/ik_llama.cpp
IKLLAMA_CPP_VERSION ?= main
ROCM_ARCHES ?= gfx1151,gfx1200,gfx1201,gfx1100,gfx1102,gfx1030,gfx1031,gfx1032

IMAGE_TAG_SUFFIX ?= 

DOCKER_CMD ?= podman
DOCKER_COMMON_ARGS = --build-arg LLAMA_SWAP_VERSION=$(LLAMA_SWAP_VERSION) --build-arg IKLLAMA_CPP_VERSION=$(IKLLAMA_CPP_VERSION) --build-arg IKLLAMA_CPP_REPO=$(IKLLAMA_CPP_REPO)  --build-arg LLAMA_CPP_VERSION=$(LLAMA_CPP_VERSION) --build-arg LLAMA_CPP_REPO=$(LLAMA_CPP_REPO) --build-arg LLAMA_CPP_INCLUDE_PRS="$(LLAMA_CPP_INCLUDE_PRS)"

build: build-vulkan build-rocm # build-zluda temporarily disabled because of CUDA header issues on Debian
 
.PHONY: build-vulkan
build-vulkan:
	$(DOCKER_CMD) build --target=llama-swap-vulkan-final --tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)$(IMAGE_TAG_SUFFIX) $(DOCKER_COMMON_ARGS) .
	$(DOCKER_CMD) tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION) quay.io/wvdschel/llama-swap:latest$(IMAGE_TAG_SUFFIX)

.PHONY: build-rocm
build-rocm:
	$(DOCKER_CMD) build --target=llama-swap-rocm-final --tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm$(IMAGE_TAG_SUFFIX) --build-arg ROCM_ARCH="$(ROCM_ARCHES)" $(DOCKER_COMMON_ARGS) .
	$(DOCKER_CMD) tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm quay.io/wvdschel/llama-swap:latest-rocm$(IMAGE_TAG_SUFFIX)
	$(DOCKER_CMD) build --target=llama-swap-rocm-igpu-final --tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm-igpu$(IMAGE_TAG_SUFFIX) --build-arg ROCM_ARCH="$(ROCM_ARCHES)" $(DOCKER_COMMON_ARGS) .
	$(DOCKER_CMD) tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm-igpu quay.io/wvdschel/llama-swap:latest-rocm-igpu$(IMAGE_TAG_SUFFIX)

.PHONY: build-zluda
build-zluda:
	$(DOCKER_CMD) build --target=llama-swap-zluda-final --tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-zluda$(IMAGE_TAG_SUFFIX) --build-arg LLAMA_SWAP_VERSION=$(LLAMA_SWAP_VERSION) --build-arg ROCM_ARCH="$(ROCM_ARCHES)"  $(DOCKER_COMMON_ARGS) .
	$(DOCKER_CMD) tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-zluda$(IMAGE_TAG_SUFFIX) quay.io/wvdschel/llama-swap:latest-zluda$(IMAGE_TAG_SUFFIX)

.PHONY: publish
publish: build
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)$(IMAGE_TAG_SUFFIX)
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm-igpu$(IMAGE_TAG_SUFFIX)
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-rocm$(IMAGE_TAG_SUFFIX)
	# $(DOCKER_CMD) push quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)-zluda$(IMAGE_TAG_SUFFIX)

.PHONY: publish-latest
publish-latest: publish
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:latest$(IMAGE_TAG_SUFFIX)
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:latest-rocm-igpu$(IMAGE_TAG_SUFFIX)
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:latest-rocm$(IMAGE_TAG_SUFFIX)
	# $(DOCKER_CMD) push quay.io/wvdschel/llama-swap:latest-zluda$(IMAGE_TAG_SUFFIX)
