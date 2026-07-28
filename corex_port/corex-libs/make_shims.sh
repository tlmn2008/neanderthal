#!/bin/bash
# CoreX(ivcore11) port helper: create CUDA-13 SONAME shim symlinks that point the
# JavaCPP CUDA-13.1 JNI at the system CoreX CUDA-10.2 libraries under /usr/local/corex.
#
# NOTE: this is an *attempted* workaround for the JavaCPP/clojurecuda CUDA-13.1 vs
# CoreX CUDA-10.2 ABI gap. It does NOT make neanderthal-cuda work — the JNI stubs
# require version-tagged symbols (foo@libcublas.so.13) that CoreX 10.2 does not
# provide (its symbols are unversioned). See ../blockers.json / ../build/abi_probe.log.
set -eu
C=/usr/local/corex/lib64
D="$(cd "$(dirname "$0")" && pwd)"
ln -sf "$C"/libcudart.so.10.2.89     "$D"/libcudart.so.13
ln -sf "$C"/libcublas.so.10.2.3.254  "$D"/libcublas.so.13
ln -sf "$C"/libcublasLt.so.10.2.3.254 "$D"/libcublasLt.so.13
ln -sf "$C"/libnvrtc.so.10.2.89      "$D"/libnvrtc.so.13
ln -sf "$C"/libcusolver.so.10.3.0.89 "$D"/libcusolver.so.12
ln -sf "$C"/libcusparse.so.10        "$D"/libcusparse.so.12
echo "shim symlinks created in $D"
