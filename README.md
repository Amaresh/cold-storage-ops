# cold-storage-ops

Deployment automation for the cold-storage runtime on `manual-crawler` (`206.189.141.91`).

## Managed projects

- `cold-storage-backend` — builds the Spring Boot jar on-host, updates `/srv/cold-storage-backend/app.jar`, and restarts `cold-storage-backend.service`
- `cold-storage-buyer-discovery` — updates the worker checkout under `/opt/cold-storage-buyer-discovery`, installs systemd units, and leaves the timer disabled by default unless explicitly enabled

## Deployment flow

```text
source repo push/workflow_dispatch
  -> repository_dispatch to Amaresh/cold-storage-ops
  -> .github/workflows/deploy.yml
  -> SSH into manual-crawler
  -> clone/update /opt/cold-storage-ops
  -> run deploy/scripts/<project>.sh
```

The ops repo also supports `workflow_dispatch` for manual deploys.

## Required GitHub repo secrets

Set these in `Amaresh/cold-storage-ops`:

- `DEPLOY_HOST_CRAWLER` — `206.189.141.91`
- `DEPLOY_SSH_KEY_CRAWLER` — private SSH key that can log into `manual-crawler` as `root`
- `REPO_SYNC_GITHUB_TOKEN` — GitHub token the host can use to clone or update private source repos such as `Amaresh/cold-storage-backend`

Host prerequisite for backend deploys:

- Java 21 must be installed on `manual-crawler`. The current backend service uses `/opt/java-21-openjdk-amd64`, and the deploy script builds with that toolchain so Maven matches the runtime.

To enable automatic cross-repo dispatch from project repos, also set this secret in each source repo:

- `OPS_REPO_DISPATCH_TOKEN` — GitHub token with permission to dispatch workflows in `Amaresh/cold-storage-ops`

## Manual deploy examples

```bash
gh api repos/Amaresh/cold-storage-ops/dispatches \
  --method POST \
  -f event_type=deploy \
  -F client_payload[project]=cold-storage-backend \
  -F client_payload[ref]=<commit-sha> \
  -F client_payload[repo]=Amaresh/cold-storage-backend
```

```bash
gh workflow run deploy.yml -R Amaresh/cold-storage-ops \
  -f project=cold-storage-buyer-discovery \
  -f ref=<commit-sha> \
  -f enable_timer=false
```

## Host layout

- Ops repo checkout: `/opt/cold-storage-ops`
- Backend source checkout: `/opt/cold-storage-backend-src`
- Backend runtime jar: `/srv/cold-storage-backend/app.jar`
- Worker checkout: `/opt/cold-storage-buyer-discovery`
- Worker env file: `/etc/cold-storage/cold-storage-buyer-discovery.env`
- Worker service: `cold-storage-buyer-discovery.service`
- Worker timer: `cold-storage-buyer-discovery.timer`
