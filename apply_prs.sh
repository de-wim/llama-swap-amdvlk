#!/bin/bash
set -exo pipefail

if [[ ${#} -lt 1 ]]; then
  echo no list of PRS provided
  exit 0
fi

for i in ${@}; do
  export PATCH=/build/${i}.patch
  wget -q https://github.com/ggml-org/llama.cpp/pull/${i}.patch -O- > ${PATCH}
  (cd /build/llama.cpp; patch -p1 ${PATCH})
done
