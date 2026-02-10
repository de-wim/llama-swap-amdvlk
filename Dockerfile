FROM archlinux:latest AS base
RUN pacman -Syyu --noconfirm wget vulkan-icd-loader

FROM base AS builder
WORKDIR /build
RUN pacman -S --noconfirm cmake git-lfs git wget go npm llvm clang ccache python make patch pkgconfig
ARG LLAMA_SWAP_VERSION
RUN git clone -b $LLAMA_SWAP_VERSION --single-branch https://github.com/mostlygeek/llama-swap --depth 1
RUN make -C /build/llama-swap clean linux

ARG LLAMA_CPP_REPO
ARG LLAMA_CPP_VERSION
ARG LLAMA_CPP_INCLUDE_PRS
RUN git clone -b ${LLAMA_CPP_VERSION} ${LLAMA_CPP_REPO} --depth 1
ADD apply_prs.sh /build/apply_prs.sh
RUN /build/apply_prs.sh ${LLAMA_CPP_INCLUDE_PRS}

# Build ik_llama.cpp
ARG IKLLAMA_CPP_REPO
ARG IKLLAMA_CPP_VERSION
RUN pacman -S --noconfirm blas cblas openblas lapack lapacke
RUN git clone -b ${IKLLAMA_CPP_VERSION} ${IKLLAMA_CPP_REPO} --depth 1
RUN cd /build/ik_llama.cpp && cmake -B build -DCMAKE_INSTALL_PREFIX=/opt/ikllama.cpp -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DGGML_STATIC=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS -DGGML_RPC=ON -DCMAKE_INSTALL_RPATH="/usr/local/cuda-13.1/lib;\$ORIGIN"
RUN cd /build/ik_llama.cpp && nice cmake --build build/ -j$(nproc)

# Build Vulkan version
RUN pacman -S --noconfirm vulkan-headers vulkan-tools glslang shaderc
RUN cd /build/llama.cpp && cmake -B build-vulkan -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DGGML_STATIC=ON -DGGML_VULKAN=ON-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS -DGGML_RPC=ON
RUN cd /build/llama.cpp && nice cmake --build build-vulkan/ -j$(nproc)

# Build ROCm version
ARG ROCM_ARCH
RUN pacman -S --noconfirm rocm-core rocminfo rocm-hip-sdk rocwmma rocm-cmake
ENV ROCM_PATH=/opt/rocm
ENV HIP_PATH=/opt/rocm
ENV HIPCXX=/opt/rocm/lib/llvm/bin/clang
RUN cd /build/llama.cpp && cmake -B build-rocm -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DCMAKE_BUILD_TYPE=Release -DGGML_HIP=ON -DGPU_TARGETS=${ROCM_ARCH} -DGGML_RPC=ON -DGGML_HIP_ROCWMMA_FATTN=ON
RUN cd /build/llama.cpp && nice cmake --build build-rocm/ -j$(nproc)

# Build CUDA / ZLUDA version
ARG CUDA_ARCH
RUN pacman -S --noconfirm cuda
RUN cd /build/llama.cpp && cmake -B build-cuda -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DGGML_RPC=ON -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" -DGGML_CUDA_FORCE_CUBLAS=1 -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc -DCMAKE_INSTALL_RPATH="/opt/cuda/lib;\$ORIGIN" -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
RUN cd /build/llama.cpp && nice cmake --build build-cuda/ -j$(nproc)

ADD ./collect_libraries.py /build/collect_libraries.py
RUN cd /build/llama.cpp/build-rocm && mkdir lib && /build/collect_libraries.py bin/llama-server ./lib/
RUN cd /build/llama.cpp/build-cuda && mkdir lib && /build/collect_libraries.py bin/llama-server ./lib/

FROM base AS llama-swap-intermediate
RUN mkdir -p /cache/mesa_shader_cache /cache/mesa_shader_cache_db /cache/radv_builtin_shaders
RUN chmod -R a+rw /cache
RUN mkdir -p /app/lib
COPY --from=builder /build/llama-swap/build/llama-swap-linux-amd64 /app/llama-swap
COPY --from=builder /build/ik_llama.cpp/build/bin/llama-server /app/ikllama-server
COPY --from=builder /build/llama.cpp/build-vulkan/bin/llama-server /app/llama-server-vulkan
COPY --from=builder /build/llama.cpp/build-rocm/bin/llama-server /app/llama-server-rocm
COPY --from=builder /build/llama.cpp/build-rocm/lib/* /app/lib/
COPY --from=builder /build/llama.cpp/build-cuda/bin/llama-server /app/llama-server-cuda
COPY --from=builder /build/llama.cpp/build-cuda/lib/* /app/lib/
RUN ln -s /app/llama-server-vulkan /app/llama-server

COPY --from=builder /build/llama.cpp/build-cuda/lib/* /app/lib/
COPY --from=builder /build/llama.cpp/build-rocm/lib/* /app/lib/
ADD ./remove-unnecessary-libs.sh /app/remove-unnecessary-libs.sh
RUN /app/remove-unnecessary-libs.sh
RUN rm /app/remove-unnecessary-libs.sh
ENV LD_LIBRARY_PATH=/app/lib

# Install ZLUDA
RUN wget -q https://github.com/vosen/ZLUDA/releases/download/v6-preview.55/zluda-linux-a5ecf6a.tar.gz -O zluda.tar.gz
RUN tar xf ./zluda.tar.gz -C /opt/ && rm zluda.tar.gz
ADD ./llama-server-zluda.sh /app/llama-server-zluda

FROM scratch AS llama-swap
COPY --from=llama-swap-intermediate / /
ENV XDG_CACHE_HOME=/cache
ENV LD_LIBRARY_PATH=/app/lib
ENTRYPOINT [ "/app/llama-swap", "-config", "/app/config.yaml" ]
