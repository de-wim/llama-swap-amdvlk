FROM debian:testing AS base
RUN apt-get update && apt-get dist-upgrade -yy
RUN apt-get install -yy vulkan-tools libcurlpp0t64 wget git
RUN apt-get clean

FROM base AS source
ARG BUILD_TIME
WORKDIR /build
RUN echo ${BUILD_TIME}

# llama-swap
ARG LLAMA_SWAP_VERSION
RUN git clone -b $LLAMA_SWAP_VERSION --single-branch https://github.com/mostlygeek/llama-swap --depth 1

# llama.cpp
ARG LLAMA_CPP_REPO
ARG LLAMA_CPP_VERSION
ARG LLAMA_CPP_INCLUDE_PRS
RUN git clone -b ${LLAMA_CPP_VERSION} ${LLAMA_CPP_REPO} --depth 1
ADD apply_prs.sh /build/apply_prs.sh
RUN /build/apply_prs.sh ${LLAMA_CPP_INCLUDE_PRS}

# ikllama
ARG IKLLAMA_CPP_REPO
ARG IKLLAMA_CPP_VERSION
RUN git clone -b ${IKLLAMA_CPP_VERSION} ${IKLLAMA_CPP_REPO} --depth 1


FROM base AS builder
WORKDIR /build
# Install packages BEFORE copying the source to avoid redownloading everything all the time
RUN apt-get install -yy libvulkan-dev glslc glslang-tools glslang-dev python3-dev build-essential cmake libcurlpp-dev golang npm llvm clang ccache
ADD ./rocm.list /etc/apt/sources.list.d/rocm.list
ADD ./rocm-pin-600 /etc/apt/preferences.d/rocm-pin-600
ADD ./rocm.gpg /etc/apt/keyrings/rocm.gpg
RUN apt-get update -yy && apt-get install -yy python3-setuptools python3-wheel rocm rocm-hip-sdk rocm-dev rocwmma-dev
RUN ln -s /usr/lib/x86_64-linux-gnu/libxml2.so /opt/rocm/lib/libxml2.so.2

# Copy sources
COPY --from=source /build /build

# Build llama-swap
RUN make -C /build/llama-swap clean linux

# Build ikllama
RUN cd /build/ik_llama.cpp && cmake -B build -DCMAKE_INSTALL_PREFIX=/opt/ikllama.cpp -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DGGML_STATIC=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS -DGGML_RPC=ON -DCMAKE_INSTALL_RPATH="/usr/local/cuda-13.1/lib;\$ORIGIN"
RUN cd /build/ik_llama.cpp && nice cmake --build build/ -j$(nproc)

# Build llama.cpp with Vulkan
RUN cd /build/llama.cpp && cmake -B build-vulkan -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DGGML_STATIC=ON -DGGML_VULKAN=ON -DGGML_RPC=ON
RUN cd /build/llama.cpp && nice cmake --build build-vulkan/ -j$(nproc)

ADD ./collect_libraries.py /build/collect_libraries.py
RUN mkdir /build/lib
RUN /build/collect_libraries.py /build/llama.cpp/build-vulkan/bin/llama-server /build/lib/

# Build llama.cpp with ROCm
FROM builder AS builder-rocm
ARG ROCM_ARCH
RUN cd /build/llama.cpp && cmake -B build-rocm -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DCMAKE_BUILD_TYPE=Release -DGGML_HIP=ON -DGPU_TARGETS=${ROCM_ARCH} -DGGML_RPC=ON -DGGML_HIP_ROCWMMA_FATTN=ON
RUN cd /build/llama.cpp && nice cmake --build build-rocm/ -j$(nproc)
RUN /build/collect_libraries.py /build/llama.cpp/build-rocm/bin/llama-server   /build/lib/

# CUDA / ZLUDA
# FROM builder AS builder-cuda
# RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb -O cuda-keyring.deb
# RUN apt-get install -yy ./cuda-keyring.deb && apt-get update
# RUN apt-get install -yy cuda-toolkit
# RUN ln -s /usr/local/cuda-13.1/targets/x86_64-linux/lib/stubs/libcuda.so /usr/local/cuda-13.1/targets/x86_64-linux/lib/stubs/libcuda.so.1
# ADD ./cuda_math_h.patch /build/
# RUN patch /usr/local/cuda-13.1/targets/x86_64-linux/include/crt/math_functions.h /build/cuda_math_h.patch
# RUN cd /build/llama.cpp && cmake -B build-cuda -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DGGML_RPC=ON -DCMAKE_CUDA_ARCHITECTURES="75;86;89" -DGGML_CUDA_FORCE_CUBLAS=1 -DCMAKE_CUDA_COMPILER=/usr/local/cuda-13.1/bin/nvcc -DCMAKE_INSTALL_RPATH="/usr/local/cuda-13.1/lib;\$ORIGIN" -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
# RUN cd /build/llama.cpp && nice cmake --build build-cuda/ -j$(nproc)
# RUN /build/collect_libraries.py /build/llama.cpp/build-cuda/bin/llama-server  /build/lib/

RUN md5sum /build/llama.cpp/build-*/bin/llama-server

FROM base AS llama-swap
RUN mkdir -p /cache/mesa_shader_cache /cache/mesa_shader_cache_db /cache/radv_builtin_shaders
RUN chmod -R a+rw /cache
RUN mkdir /app
COPY --from=builder /build/llama-swap/build/llama-swap-linux-amd64        /app/llama-swap
COPY --from=builder /build/ik_llama.cpp/build/bin/llama-server            /app/ikllama-server
COPY --from=builder /usr/lib/x86_64-linux-gnu/libgomp*                    /app/
COPY --from=builder /build/llama.cpp/build-vulkan/bin/llama-server        /app/llama-server-vulkan
COPY --from=builder-rocm /build/llama.cpp/build-rocm/bin/llama-server     /app/llama-server-rocm
# COPY --from=builder-cuda /build/llama.cpp/build-cuda/bin/llama-server     /app/llama-server-cuda
COPY --from=builder      /build/lib/*                                     /app/lib/
COPY --from=builder-rocm /build/lib/*                                     /app/lib/
# COPY --from=builder-cuda /build/lib/*                                     /app/lib/
RUN ln -s /app/llama-server-vulkan /app/llama-server
RUN md5sum /app/llama-server*

ADD ./remove-unnecessary-libs.sh /app/remove-unnecessary-libs.sh
RUN /app/remove-unnecessary-libs.sh

# ZLUDA setup
# ADD ./llama-server-zluda.sh /app/llama-server-zluda
# RUN wget -q https://github.com/vosen/ZLUDA/releases/download/v6-preview.55/zluda-linux-a5ecf6a.tar.gz -O zluda.tar.gz
# RUN tar xf ./zluda.tar.gz -C /opt/ && rm zluda.tar.gz

FROM scratch AS llama-swap-final
COPY --from=llama-swap / /
ENV XDG_CACHE_HOME=/cache
ENV LD_LIBRARY_PATH=/app/lib
ENTRYPOINT [ "/app/llama-swap", "-config", "/app/config.yaml" ]
