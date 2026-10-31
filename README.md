# platform-deployments

How the MERN shop **runs** on Kubernetes and how new versions reach the three clusters: one reusable Helm chart, per-service and per-cloud values, the Jenkins pipelines (deploy, backup, restore drill), the disaster-recovery scripts, the seed job and a Docker Compose setup for running the whole shop on a laptop.

## Contents

| Path | Purpose |
|---|---|
| `charts/microservice/` | one Helm chart for every service: Deployment (rolling update `maxUnavailable: 0`, probes, `preStop` drain, non-root, read-only filesystem), Service, HPA, PodDisruptionBudget, HTTPRoute, ExternalSecret, ServiceMonitor, NetworkPolicy, ServiceAccount |
| `values/services/<service>.yaml` | per-service settings: port, probes, resources, routes, allowed callers, secrets |
| `values/clouds/<cloud>.yaml` | per-cloud settings: cloud label, image registry, hostnames |
| `pipelines/deploy.Jenkinsfile` | `deploy-mern`: deploy one service version to GCP → Azure → AWS with a smoke test after each, automatic rollback, sleeping standbys skipped, Slack messages |
| `pipelines/backup.Jenkinsfile` | `backup-mongo`: nightly encrypted `mongodump` → GCS + S3 + Azure Blob |
| `pipelines/restore-drill.Jenkinsfile` | `restore-drill`: restore the newest backup from one cloud into a scratch database and compare document counts |
| `scripts/dr/` | the backup/restore steps used by those pipelines (dump, upload, download, verify, keyless secret fetch) |
| `jobs/seed-db.yaml` | one-off Kubernetes Job that seeds the shared database |
| `local/` | Docker Compose for the whole shop + MongoDB on a laptop — see `local/README.md` |

## Dependencies

| Depends on | For |
|---|---|
| service repos ([api-gateway](https://github.com/ppmcad16a-cloud-platform/api-gateway-service), [identity](https://github.com/ppmcad16a-cloud-platform/identity-service), [catalog](https://github.com/ppmcad16a-cloud-platform/catalog-service), [commerce](https://github.com/ppmcad16a-cloud-platform/commerce-service), [notification](https://github.com/ppmcad16a-cloud-platform/notification-service), [client](https://github.com/ppmcad16a-cloud-platform/client-service), [seed-db](https://github.com/ppmcad16a-cloud-platform/seed-db-service)) | the images it deploys (`main-<sha>` tags in ECR, ACR, Artifact Registry) |
| [gcp-platform](https://github.com/ppmcad16a-cloud-platform/gcp-platform) | Jenkins itself and its job definitions (they load the pipelines from this repo) |
| cloud add-ons from the three cloud repos | Envoy Gateway (`HTTPRoute`), External Secrets store `cloud-vault`, Prometheus (`ServiceMonitor`) |

| Used by | For |
|---|---|
| Jenkins in GKE | the three pipelines |
| [platform-automation](https://github.com/ppmcad16a-cloud-platform/platform-automation) | installs the shop with this chart (`up.yml`, `wake.yml`, `deploy.yml`) |
| [core-cloud-platform](https://github.com/ppmcad16a-cloud-platform/core-cloud-platform) `trigger-deploy.yaml` | starts `deploy-mern` after a merge |

## Usage

Deploy one service by hand (what Jenkins and the playbooks run):

```bash
helm upgrade --install catalog-service charts/microservice --namespace mern \
  -f values/clouds/gcp.yaml -f values/services/catalog-service.yaml \
  --set image.tag=main-ba5cc42 --rollback-on-failure --wait --timeout 8m
```

Jenkins → `deploy-mern` → *Build with Parameters*: `SERVICE`, `IMAGE_TAG`, `TARGETS` (default `gcp,azure,aws`). To roll back, deploy the previous tag.

Check the chart: `helm lint charts/microservice -f values/clouds/gcp.yaml -f values/services/catalog-service.yaml`.

Run the shop locally:

```bash
cd local && cp .env.example .env      # set JWT_SECRET and the seed admin
docker compose up --build -d && docker compose --profile seed run --rm seed
# http://localhost:8080
```
