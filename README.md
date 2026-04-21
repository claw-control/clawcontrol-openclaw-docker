# ClawControl OpenClaw Docker Example

This repository shows how to run a self-managed OpenClaw gateway together with
the ClawControl runtime in Docker.

It is a complete example project that you can use directly or adapt for your
own environment.

## Start With The Docs Guide

For the full setup walkthrough, use the ClawControl docs:

[Run OpenClaw and the runtime in Docker](https://clawcontrol.dev/docs/guides/run-openclaw-and-runtime-in-docker)

That guide covers:

- prerequisites
- environment configuration
- bringing up the Docker stack
- onboarding OpenClaw
- pairing the runtime to ClawControl
- verification and day-2 operations

## What This Repo Includes

- `docker-compose.yml` for the OpenClaw gateway, helper CLI, and runtime
- `.env.example` with the main knobs you are expected to change
- `Dockerfile.runtime` that installs the published `@clawcontrol/runtime`
  package into the OpenClaw base image
- `stack.sh` for common local commands such as build, up, logs, pairing, and
  approval
- `openclaw.json` template used to seed the gateway config on first run

## Quick Start

Clone the repository:

```bash
git clone https://github.com/claw-control/clawcontrol-openclaw-docker.git
cd clawcontrol-openclaw-docker
```

Create the local env file:

```bash
cp .env.example .env
```

Review at least these values in `.env`:

- `OPENCLAW_IMAGE`
- `OPENCLAW_GATEWAY_TOKEN`
- `CLAWCONTROL_RUNTIME_NPM_SPEC`
- `OPENCLAW_GATEWAY_PORT`
- `OPENCLAW_BROWSER_UI_PORT`

Build and start the stack:

```bash
./stack.sh up --build
```

If this is a fresh OpenClaw state directory, onboard OpenClaw:

```bash
./stack.sh onboard
```

Create a pairing code in ClawControl, then pair the runtime:

```bash
./stack.sh pair <PAIRING_CODE> --name "Docker Runtime"
```

If the gateway reports pending device approvals, approve them:

```bash
./stack.sh approve-pending
```

Check runtime status:

```bash
./stack.sh runtime runtime status
```

## Default Endpoints

- OpenClaw browser UI: `http://127.0.0.1:18801`
- OpenClaw gateway: `ws://127.0.0.1:18799`

## Persistent Data

By default, the repository stores runtime data next to the stack files:

- `state/openclaw` for OpenClaw state
- `state/runtime` for runtime config and state
- `workspace` for the mounted OpenClaw workspace

If you want to move those directories elsewhere, set these optional values in
`.env`:

- `OPENCLAW_STATE_DIR`
- `OPENCLAW_WORKSPACE_DIR`
- `RUNTIME_STATE_DIR`

## Useful Commands

```bash
./stack.sh ps
./stack.sh logs
./stack.sh logs runtime
./stack.sh restart --build
./stack.sh pull-openclaw
./stack.sh shell-openclaw
./stack.sh shell-runtime
./stack.sh runtime runtime logs --follow
./stack.sh down
```

## Notes

- `CLAWCONTROL_RUNTIME_NPM_SPEC=latest` is convenient for testing, but an exact
  version is better when you want repeatable installs.
- The runtime image installs the published `@clawcontrol/runtime` package during
  Docker build time.
- The runtime package uses its bundled production defaults for pinned backend
  endpoints and trust roots.
- The helper CLI and runtime share the same mounted OpenClaw state so gateway
  state and plugin state stay aligned.

## License

This repository is licensed under the MIT License. See [LICENSE](./LICENSE).
