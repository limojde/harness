# Limoj CI harness — a GitHub Actions runner with the full Limoj toolchain
# plus the claude and opencode CLIs.
#
# Base must be the official actions-runner image: ARC starts the pod with
# /home/runner/run.sh, which only exists here. Building "from scratch" with a
# hand-rolled runner agent is not supported by gha-runner-scale-set.
FROM ghcr.io/actions/actions-runner:2.336.0

USER root

# No compiler here on purpose: python and ruby are installed as precompiled
# binaries (see MISE_*_COMPILE below), so the image only needs the shared
# libraries those binaries link against, not the -dev headers to build them.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      git-lfs \
      gnupg \
      jq \
      libffi8 \
      libyaml-0-2 \
      unzip \
      xz-utils \
      zlib1g \
    && rm -rf /var/lib/apt/lists/*

# mise owns every language and CLI version in this image. Installing to /opt
# rather than ~runner keeps the toolchain out of the workspace volume that
# actions/checkout clobbers.
#
# MISE_PYTHON_COMPILE / MISE_RUBY_COMPILE=false make mise fetch prebuilt
# binaries and *fail* if none exist for the pinned version, instead of
# silently falling back to a from-source build that needs build-essential.
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    MISE_YES=1 \
    MISE_PYTHON_COMPILE=false \
    MISE_RUBY_COMPILE=false \
    PATH=/opt/mise/shims:/usr/local/bin:$PATH

RUN curl -fsSL https://mise.run | sh && mise --version

COPY mise.toml /opt/mise/config.toml

# `mise trust` is required for a config outside $HOME; without it every later
# `mise exec` in a job prompts and hangs.
RUN mise trust /opt/mise/config.toml \
    && mise install \
    && mise reshim \
    && chown -R runner:runner /opt/mise \
    && rm -rf /tmp/mise-cache

USER runner

# Fail the build rather than ship an image where a tool silently didn't land.
RUN claude --version \
    && opencode --version \
    && go version \
    && bun --version \
    && python --version \
    && ruby --version \
    && kubectl version --client \
    && docker --version
