# Uncomment and edit to build experimental versions
#LLAMA_CPP_REPO = https://github.com/pwilkin/llama.cpp
#LLAMA_CPP_VERSION = autoparser
IMAGE_TAG_SUFFIX =

LLAMA_SWAP_VERSION = v190
LLAMA_CPP_REPO ?= https://github.com/ggml-org/llama.cpp
LLAMA_CPP_VERSION ?= master
# Add PR numbers for unmerged PRs to include in this build here
# PR 18675: autoparser PR that enables toolcalling for most grammars
LLAMA_CPP_INCLUDE_PRS=18675
IKLLAMA_CPP_REPO ?= https://github.com/ikawrakow/ik_llama.cpp
IKLLAMA_CPP_VERSION ?= main
ROCM_ARCH ?= gfx1151,gfx1200,gfx1201,gfx1100,gfx1102,gfx1030,gfx1031,gfx1032
CUDA_ARCH ?= 75;86;89

IMAGE_TAG_SUFFIX ?=

DOCKER_CMD ?= podman
DOCKER_COMMON_ARGS = --build-arg ROCM_ARCH="$(ROCM_ARCH)" --build-arg CUDA_ARCH="$(CUDA_ARCH)"  --build-arg LLAMA_SWAP_VERSION=$(LLAMA_SWAP_VERSION) --build-arg IKLLAMA_CPP_VERSION=$(IKLLAMA_CPP_VERSION) --build-arg IKLLAMA_CPP_REPO=$(IKLLAMA_CPP_REPO)  --build-arg LLAMA_CPP_VERSION=$(LLAMA_CPP_VERSION) --build-arg LLAMA_CPP_REPO=$(LLAMA_CPP_REPO) --build-arg LLAMA_CPP_INCLUDE_PRS="$(LLAMA_CPP_INCLUDE_PRS)"

.PHONY: build
build:
	$(DOCKER_CMD) build --target=llama-swap --tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)$(IMAGE_TAG_SUFFIX) $(DOCKER_COMMON_ARGS) .
	$(DOCKER_CMD) tag quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)$(IMAGE_TAG_SUFFIX) quay.io/wvdschel/llama-swap:latest$(IMAGE_TAG_SUFFIX)

.PHONY: publish
publish: build
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:$(LLAMA_SWAP_VERSION)$(IMAGE_TAG_SUFFIX)

.PHONY: publish-latest
publish-latest: publish
	$(DOCKER_CMD) push quay.io/wvdschel/llama-swap:latest$(IMAGE_TAG_SUFFIX)
