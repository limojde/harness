# harness

The container image Limoj's self-hosted GitHub Actions runners boot from.

It is an official `actions-runner` image plus the Limoj toolchain (go, bun,
python/uv, ruby, the Kubernetes and sops tooling) and the two agent CLIs,
`claude` and `opencode`. Everything except the OS packages is managed by
[mise](https://mise.jdx.dev) via [`mise.toml`](./mise.toml).

The same image also backs the long-running `opencode serve` Deployment in
`platform` (`manifests/apps/internal/opencode/`), so the reviewer running in CI
and the server n8n talks to are the same binaries at the same versions.

```
ghcr.io/limojde/harness:latest
ghcr.io/limojde/harness:<git-sha>
```

## ⚠️ Bootstrap: the first build cannot run in CI

`.github/workflows/build-image.yaml` uses `runs-on: limoj-k8s` — the ARC scale
set whose runner pods run **this image**. Until a tag exists in ghcr, the scale
set has nothing to pull, so there is no runner to build it on.

Break the cycle once, locally, on the rootless podman machine:

```sh
# Confirm the rootless machine is the running one before you start —
# limoj-kind is rootful and only one machine runs at a time.
podman machine list

podman build -t ghcr.io/limojde/harness:latest -f Containerfile .
echo "$GHCR_TOKEN" | podman login ghcr.io -u <you> --password-stdin
podman push ghcr.io/limojde/harness:latest
```

After that tag exists, Flux can start the scale set and every later build runs
on `limoj-k8s` from CI. You only ever redo this if you break the image so badly
that no runner can start — in which case the fix is another local build.

## Pinning in platform

`platform` currently references `:latest` for readability. Once this settles,
switch `manifests/apps/internal/arc-runners/spec/helmrelease.yaml` and the
opencode Deployment to the digest printed in the build job summary:

```
ghcr.io/limojde/harness@sha256:...
```

`:latest` means a Flux reconcile can silently change your runner toolchain
mid-week. A digest means the toolchain moves only in a reviewed commit.

## Adding a tool

Add it to `mise.toml` and open a PR. The PR build verifies the Containerfile
still resolves without publishing anything; merging to `main` publishes.

The final `RUN` in the Containerfile asserts each headline tool is on `PATH`.
Add an assertion there for anything you'd be upset to discover missing at 2am.

## What's deliberately not here

The cluster-provisioning tools from `platform/mise.toml` — `kind`, `talosctl`,
`packer`, `opentofu`, `hcloud`. Those are for operators on a laptop, not for
jobs on a runner, and they add roughly 400MB to every runner pod's pull.

If a workflow genuinely needs one, prefer a second scale set with a second
image over inflating this one.
