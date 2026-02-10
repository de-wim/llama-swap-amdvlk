#!/bin/bash
EXPORT LD_LIBRARY_PATH=/opt/zluda:/app/lib

/app/llama-server-cuda "${@}"
