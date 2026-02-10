#!/bin/bash
EXPORT LD_LIBRARY_PATH=/app:/opt/zluda:/opt/cuda

/app/llama-server-cuda "${@}"
