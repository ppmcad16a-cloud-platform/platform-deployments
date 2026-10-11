# platform-deployments

Everything needed to **run** the services on the three Kubernetes clusters (EKS, AKS, GKE).

> **In plain words:** the service repos produce container images. This repo describes *how* those
> images run (how many copies, health checks, memory limits, routing) and contains the Jenkins
> pipelines that roll new versions out to AWS, Azure and GCP one cloud at a time.

## What lives here (Phases 6-8, 10)

| Folder | Purpose |
|---|---|
| `charts/microservice/` | One reusable Helm chart used by every service (Deployment, Service, HPA, PodDisruptionBudget, HTTPRoute, ExternalSecret, ServiceMonitor, NetworkPolicy) |
| `values/<service>.yaml`, `values/<cloud>.yaml` | Per-service settings and per-cloud differences |
| `addons/helmfile.yaml` | Cluster add-ons: Envoy Gateway, External Secrets, AWS Load Balancer Controller, autoscaler |
| `jenkins/` | Jenkins Helm values + Configuration-as-Code |
| `pipelines/` | `Jenkinsfile`s: deploy, rollback, seed DB, backup, restore drill, failover drill |
| `releases.yaml` | Record of which version of each service runs in which cloud |

## Deployment flow

```
service merged to main -> image pushed to ECR/ACR/GAR -> Jenkins deploy job
  -> GCP: helm upgrade --atomic --wait -> smoke test
  -> Azure: same
  -> AWS: same
  (any failure = automatic rollback of that cloud, pipeline stops, Slack alert)
```
