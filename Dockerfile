# syntax=docker/dockerfile:1
# -----------------------------------------------------------------------------
# ucie2-pipe7-bridge — license-free SV-UVM-on-Verilator gate (Railway / CI).
#
# Reproduces the heavy UVM gate that cannot run on the ~8 GB local host: builds
# UVM-capable Verilator from source (the apt Verilator can't elaborate UVM), then
# runs `make -C dv/uvm/vlt ci` (lint + --binary build + run, UVM_ERROR-gated).
# This project does NOT use OSS CAD Suite.
#
#   Build:  docker build -t ucie2-pipe7-uvm .
#   Run  :  docker run --rm ucie2-pipe7-uvm            # full UVM gate
#           docker run --rm ucie2-pipe7-uvm verilator --version
#   Railway: batch / run-to-completion job (see .railway/railway.ts).
# -----------------------------------------------------------------------------

# ---- Stage 1: build UVM-capable Verilator from source -----------------------
FROM ubuntu:24.04 AS verilator-build
ARG VERILATOR_REF=v5.050
ARG VERILATOR_PREFIX=/opt/verilator
ARG VL_BUILD_JOBS=2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git help2man perl python3 make autoconf g++ flex bison ccache \
      libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev \
      zlib1g zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${VERILATOR_REF}" \
      https://github.com/verilator/verilator /tmp/verilator-src
WORKDIR /tmp/verilator-src
RUN autoconf \
    && ./configure --prefix="${VERILATOR_PREFIX}" \
    && make -j"${VL_BUILD_JOBS}" \
    && make install
# `make install` skips test_regress/; keep the bundled Accellera UVM library next
# to the install so UVM_HOME is self-contained in the image.
RUN mkdir -p "${VERILATOR_PREFIX}/uvm" \
    && cp -a test_regress/t/uvm/. "${VERILATOR_PREFIX}/uvm/"

# ---- Stage 2: runtime image that builds + runs the UVM env ------------------
FROM ubuntu:24.04 AS uvm
ARG VERILATOR_PREFIX=/opt/verilator
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=UTF-8 PYTHONUTF8=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      g++ make perl python3 python3-pip ccache z3 yosys git \
      libgoogle-perftools-dev zlib1g zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# SymbiYosys (github.com/YosysHQ/sby) is pure Python -- `make install` just
# copies sbysrc/*.py into place, so a shallow clone is fast (no compile). It
# needs the `click` module at runtime. This is the formal tier (Phase F
# increment 3, `make formal`); still NOT OSS CAD Suite.
RUN pip3 install --break-system-packages --no-cache-dir click \
    && git clone --depth 1 https://github.com/YosysHQ/sby /tmp/sby \
    && make -C /tmp/sby install \
    && rm -rf /tmp/sby
COPY --from=verilator-build /opt/verilator /opt/verilator
# Leave VERILATOR_ROOT unset (a stale value hard-errors the launcher, which
# derives its root from its own path). The entrypoint unsets it defensively too.
ENV VERILATOR="${VERILATOR_PREFIX}/bin/verilator" \
    UVM_HOME="${VERILATOR_PREFIX}/uvm" \
    PATH="${VERILATOR_PREFIX}/bin:${PATH}"
# Serialize the --binary UVM precompiled-header compile (several GB per job).
ENV BUILD_JOBS=1
WORKDIR /work
COPY . /work
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# Fail fast if the toolchain is incomplete.
RUN "${VERILATOR}" --version \
    && test -f "${UVM_HOME}/uvm_pkg_all_v2020_3_1_dpi.svh" \
    && test -f "${UVM_HOME}/v2020_3_1/dpi/uvm_dpi.cc" \
    && z3 --version \
    && yosys -V \
    && sby --help >/dev/null \
    && python3 -c "import click"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
