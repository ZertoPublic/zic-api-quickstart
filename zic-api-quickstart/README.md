# Zerto In-Cloud (ZIC) API Quickstart

A small, opinionated set of working examples for the **Zerto In-Cloud
(ZIC) REST API**, in **bash + curl**, **Python**, and **PowerShell**.

This repo follows the same shape as
[ZertoPublic/zerto-api-quickstart](https://github.com/ZertoPublic/zerto-api-quickstart)
(ZVM / ZCA), but is scoped to ZIC — the AWS-native variant where the
appliance lives inside an AWS account and protects EC2 workloads
directly.

**New to REST APIs?** Read [GETTING-STARTED.md](GETTING-STARTED.md)
first — a 20-minute narrated walkthrough that takes you from "what's
an API" through reading the appliance, creating a VPG, and watching
the task finish.

If you've called REST APIs before, jump straight to
[`zic-aws/examples/01-get-token`](zic-aws/examples/01-get-token).

## Authoritative source

Everything in this repo was generated from the on-appliance Swagger
JSON. ZIC ships **two API versions side-by-side**:

```
https://<zic-host>/zic/api/swagger/v1/swagger.json    # single-account API
https://<zic-host>/zic/api/swagger/v2/swagger.json    # multi-account API
```

(The interactive Swagger UI is at
`https://<zic-host>/zic/api/help/index.html`.)

Both are OpenAPI **3.0.1**. The base URL is
`https://<zic-host>/zic`, paths under `/api/v1/...` or `/api/v2/...`.

## Which version should you use?

| Scenario | Use |
| -------- | --- |
| Single AWS account, ZIC protecting workloads in its own account only | **v1** is fine — simpler URL surface, fewer concepts. |
| Multi-account: ZIC's appliance account protecting workloads in *other* AWS accounts via cross-account IAM | **v2** — only v2 has the `/zicconfiguration/memberaccounts` CRUD and account-scoped discovery endpoints. |
| You want CMKs, IAM roles, or EC2 launch templates exposed via the API for VPG creation | **v2** — these resources are only exposed under `/api/v2/accounts/{accountId}/...`. |
| Mixed deployment, supporting both | **v2** for new automation; v1 still works for the older surface. |

### What's actually different

The two surfaces overlap heavily. Everything in v1 has an
identical-shape equivalent in v2 — same request bodies, same
response schemas, same task model, same error codes for the
inherited endpoints. The only differences:

- **Path prefix.** `/api/v1/...` vs `/api/v2/...`.
- **v2 adds member-account management.**
  `GET|POST|PUT|DELETE /api/v2/zicconfiguration/memberaccounts` plus
  a `/statistics` endpoint. No equivalent in v1.
- **v2 account-scopes discovery.** v1 has
  `/regions/{regionId}/resources/...`; v2 has
  `/accounts/{accountId}/regions/{regionId}/resources/...`. Same
  response shapes; just an extra path component for the account ID.
- **v2 exposes three new resource types** under the account-scoped
  paths: KMS customer-managed keys (`cmks`), EC2 launch templates
  (`launchtemplates`), and IAM roles (`roles`).
- **v2 uses RFC 7807 ProblemDetails** for error responses on the
  *new* endpoints (member accounts). The inherited VPG/alerts
  endpoints still use the legacy `ErrorResponse` shape even on
  `/api/v2/...`. Yes, the API mixes conventions; just be ready for
  both.

## Pick your platform

| Folder | Use this if… |
| ------ | ------------ |
| [`zic-aws/`](zic-aws) | You have a **Zerto In-Cloud appliance running in AWS**. Source workloads and recovery targets are both EC2. |

There's only one folder for now because ZIC ships AWS-only today.

## Important conceptual notes

A few things worth knowing before you start:

- **ZIC uses VPGs**, not "CRGs". The entity is the same one you know
  from ZVM/ZCA — a Virtual Protection Group, a set of VMs replicated
  together with a shared SLA.
- **Create is one-shot**, not two-step. Unlike ZVM/ZCA's
  `POST vpgSettings` → `POST .../commit` pattern, ZIC takes the
  entire VPG configuration in a single `POST /api/v1/vpgs` and
  returns a 202 — work continues asynchronously.
- **There's no separate "peer site" object.** Recovery targets in
  ZIC are AWS **regions** (and optionally **member accounts** for
  cross-account recovery). Use `GET /api/v1/regions` and
  `GET /api/v1/regions/{regionId}/resources/...` to discover what
  you can recover to.
- **No VRA model.** ZIC doesn't install a per-host replication
  appliance — there's no host to install on. The entire `/vras`
  family from ZVM has no equivalent here, and the swagger doesn't
  define one.
- **Failover uses a header for the action verb.** All recovery
  operations are `PUT /api/v1/vpgs/{vpgId}/failover` with a
  `Zic-Action` header that takes one of: `failover`,
  `failoverCommit`, `failoverRollback`, `failoverTest`,
  `failoverTestStop`.

## What each example does

| # | Example | Endpoint(s) it shows |
| - | ------- | --------------------- |
| 01 | `01-get-token` | OAuth password-grant against the appliance's Keycloak. |
| 02 | `02-list-vpgs` | `GET /api/v1/vpgs` — VPG name, state, protection status, actual RPO. |
| 03 | `03-list-regions` | `GET /api/v1/regions` — AWS regions the appliance can use for protection or recovery. |
| 04 | `04-list-vms-in-region` | `GET /api/v1/regions/{regionId}/resources/vms` — EC2 inventory, including which VMs are already protected and in which VPGs. |
| 05 | `05-list-alerts` | `GET /api/v1/alerts?isDismissed=false` — active alerts, filterable by level and VPG. |
| 06 | `06-create-vpg` | One-shot `POST /api/v1/vpgs` with a real-shape `CreateVpgRequest` body. |
| 07 | `07-monitor-task` | Polling pattern for `GET /api/v1/tasks/{taskId}` until `status` is terminal. |
| 08 | `08-failover-test` | `PUT /api/v1/vpgs/{vpgId}/failover` with `Zic-Action: failoverTest`, then `Zic-Action: failoverTestStop`. |
| 09 | `09-tag-management` | Read-modify-write on `PUT /api/v1/vpgs/{vpgId}` to add, remove, or replace `recovery.default.tags`. |
| 10 | `10-list-member-accounts` *(v2)* | `GET /api/v2/zicconfiguration/memberaccounts` — list AWS accounts the appliance can protect/recover into, plus `/statistics`. |
| 11 | `11-manage-member-accounts` *(v2)* | Full CRUD on member accounts: `POST` to onboard, `PUT` to update CMK / external ID, `DELETE` to offboard. |
| 12 | `12-list-account-resources` *(v2)* | Multiplexing CLI over `/api/v2/accounts/{accountId}/...` for VMs, VPCs, subnets, security groups, keypairs, CMKs, launch templates, IAM roles. |

Every example folder ships three runnable scripts:

```
example-name.sh    # bash + curl
example_name.py    # Python (requests)
Example-Name.ps1   # PowerShell 7+
```

Plus a per-example `README.md` explaining the endpoint, request and
response shapes, and adjacent endpoints worth exploring.

## Conventions across the repo

- **Self-signed certs are skipped** (`-k` / `verify=False` /
  `-SkipCertificateCheck`). Remove these flags if you have a properly
  signed cert on the appliance.
- **Env vars from `.env`.** The bash and Python examples auto-load
  `zic-aws/.env` if it exists. PowerShell expects environment
  variables set in the session.
- **No external runtime deps** beyond standard tooling:
  - bash: `curl`, `jq`
  - Python: `requests`
  - PowerShell: 7+ (for `-SkipCertificateCheck`)
- **Auth is re-fetched per example.** Tokens are short-lived (~60s);
  every script either calls 01 or imports its helper, so re-auth is
  automatic.

## What this repo is *not*

- A production SDK. These are read-the-source quickstart examples,
  not a robust client library. Add token refresh, structured error
  handling, and retry logic before depending on it.
- Exhaustive. The ZIC v1 swagger defines roughly 22 endpoints. These
  examples cover the 8 you'll hit first. The rest (license,
  configuration, scale accounts, checkpoints) follow identical
  patterns — auth header, JSON body, 202-and-poll on writes.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
