---
name: boomi-cloud-api-management
description: >-
  Operates Boomi Cloud API Management (CAM), the SaaS API management platform formerly known as TIBCO Cloud API Management or Mashery. Use when the user works with CAM or Mashery APIs, endpoints, packages, plans, applications, or API keys. Not for the Boomi API Gateway or API Control Plane (ACP).
---

# boomi-cloud-api-management

CAM is a hosted API proxy with a developer portal. Its Traffic Manager takes calls on a public domain and path and forwards them to a backend host. It checks keys and plan limits on each call. Admins use the API Control Center UI. This skill drives the V3 management REST API through scripts.

## Scope

In: CAM SaaS services, endpoints, packages, plans, applications, package keys, domains, and OpenAPI import.

Out:
- CAM Local Edition (on-prem).
- Boomi API Gateway → `boomi-api-gateway`.
- API Control Plane → `boomi-api-control-plane`.
- Boomi Integration processes and API Service components → `boomi-integration`.

Not scripted: reporting, V2 JSON-RPC, OAuth security profiles, member create, roles, methods. Reach these with `cam-api.sh`.

## Object model

| Object | What it is | Parent |
|---|---|---|
| Service | One API definition | Area |
| Endpoint | Public domain + path → backend host + path. Holds key detection, backend auth, and policies. | Service |
| Method | A named operation the Traffic Manager detects | Endpoint |
| Package | A group of plans | Area |
| Plan | Grants endpoints. Sets QPS and quota limits. | Package |
| Member | An area user or portal developer | Area |
| Application | A member's registered app. Holds keys. | Member |
| Package Key | Consumer credential for one application, package, and plan | Application |
| Domain | A whitelisted host for endpoint public domains | Area |

- An area is one CAM tenant. It is identified by a UUID.
- A plan grants nothing until its `services[]` lists endpoints.
- One application holds one key per package and plan.

## Setup

The scripts read credentials from the workspace `.env`. Never pass a credential on a command line.

```
CAM_API_KEY=
CAM_API_SECRET=
CAM_USERNAME=
CAM_PASSWORD=
CAM_AREA_UUID=
CAM_API_URL=https://api.mashery.com
CAM_QPS=2
```

| Key | Where it comes from |
|---|---|
| `CAM_API_KEY`, `CAM_API_SECRET` | Issue a "Mashery API: V2 + V3" key at developer.mashery.com ([guide](https://developer.mashery.com/docs/read/mashery_api/30/Using_the_Mashery_API_for_your_area)). Access to the key and to each area may need approval. |
| `CAM_USERNAME`, `CAM_PASSWORD` | An area user, such as the area's service account (Service User role). |
| `CAM_AREA_UUID` | Control Center → **?** (top right) → Area Information. The API cannot return it. |
| `CAM_API_URL` | Optional. Defaults to `https://api.mashery.com`. |
| `CAM_QPS` | Optional. Defaults to 2. Raise it only after Boomi Support raises the key's limit. |

Then run `bash <skill-path>/scripts/cam-env-check.sh` from the workspace.

## `<skill-path>` resolution

- Take the absolute path of this SKILL.md and drop `/SKILL.md`. That is `<skill-path>`.
- `cam-env-check.sh` doubles as the path check.
- Treat `<skill-path>` as fixed for the session.

## Scripts

All scripts take `--help`. They print JSON to stdout and errors to stderr. They exit non-zero on failure.

- Create and update take a JSON body **file**. Write the body to a file under `active-development/cam/`, then run the script.
- Every call counts against the key's budget. The scripts throttle and retry.

| Script | Subcommands |
|---|---|
| `cam-env-check.sh` | (none). Checks `.env`, gets a token, makes one call. |
| `cam-api.sh` | `METHOD PATH [BODY_FILE] [--show]`. Raw GET, POST, or PUT for anything not scripted. DELETE is refused. |
| `cam-service.sh` | `list`, `get SID`, `create FILE`, `update SID FILE` |
| `cam-endpoint.sh` | `list SID`, `get SID EID`, `create SID FILE`, `update SID EID FILE` |
| `cam-package.sh` | `list`, `get PID`, `create FILE`, `update PID FILE`, `plan-create PID FILE`, `plan-get PID PLID`, `plan-update PID PLID FILE`, `plan-add-endpoint PID PLID SID EID`, `plan-remove-endpoint PID PLID SID EID` |
| `cam-app.sh` | `members [USERNAME]`, `list [MEMBER_ID]`, `get AID`, `create USERNAME NAME` |
| `cam-key.sh` | `list [AID] [--show]`, `create AID PID PLID [--show]`, `enable KID`, `disable KID`, `call KID URL [--header NAME \| --param NAME]` |
| `cam-domain.sh` | `list`, `create DOMAIN [DESCRIPTION]` |
| `cam-import.sh` | `FILE [--format oas3\|swagger2] --public-domain DOMAIN [--create]` |

- `cam-key.sh list`, `cam-key.sh create`, and `cam-api.sh` mask keys, secrets, and passwords. Use `--show` only when the user asks.

## Workflow: expose an API

1. `cam-domain.sh list`. The endpoint's public domain must be whitelisted. If it is missing, confirm with the user, then `cam-domain.sh create`. The API cannot delete a domain.
2. `cam-service.sh create FILE`. Only `name` is required.
3. `cam-endpoint.sh create SID FILE`. `references/request_body.md` lists the fields and allowed values.
   - Alternative to steps 2–3: `cam-import.sh` turns an OpenAPI file into a service.
4. `cam-package.sh create FILE`.
5. `cam-package.sh plan-create PID FILE`. List the service and endpoint IDs inline in `services[]`.
6. `cam-app.sh members USERNAME` to find the member by exact username. Then `cam-app.sh create USERNAME NAME`.
7. `cam-key.sh create AID PID PLID`. A new key can land in `waiting`. Run `cam-key.sh enable KID` to activate it.
8. Test with `cam-key.sh call KID https://<public-domain>/<requestPathAlias>`. Match `--header` or `--param` to the endpoint's key location. The key stays masked.
   - The default traffic domain is `<area-name>.api.mashery.com`.
   - A new key can take some time to become active.
   - A 403 "Developer Inactive" can mean a missing key, a key not yet live, or no plan granting the endpoint.

To change a plan's endpoints later, use `plan-add-endpoint` or `plan-remove-endpoint`.

## Rules

- Scripts do not delete. Deletes are done by the user in Control Center. To stop access without deleting, use `cam-key.sh disable` or `plan-remove-endpoint`.
- Confirm with the user before changing an endpoint, plan, or key that serves live traffic.
- Update files carry scalar fields only. Never include `endpoints`, `plans`, `services`, or `methods`. The scripts refuse them. Use the child subcommand instead.
- Confirm with the user before `cam-domain.sh create`. The domain stays until someone removes it in the UI.
- The default key budget is 2 calls per second and 5,000 per day.
- Report a failure to the user with the HTTP code and body.

## UI or Support only

- Custom domain CNAME, TLS certificate, and approval.
- All deletes. The scripts do not delete; domain delete is also 403 in the API.
- Keyless (open) endpoints. The API has no such auth type.
- Application status. Apps read `draft`, and that does not block keys.
- Raising the management key's QPS limit (Support).
- Event triggers (Support).
- OAuth 2.0 Accelerator enablement.
- Call log stream and export setup.
- Portal content and styling. No API is documented.

## API Control Plane

- ACP can manage a CAM area. An ACP subscription approval writes a package and package key into CAM.
- An ACP plan change deletes and recreates that key.
- Ask the user before editing ACP-created packages or keys directly.

## Boomi Integration

- To front a Boomi Integration API Service, build and deploy it with `boomi-integration`. Then point the endpoint's `systemDomains` at its runtime host.
- The CAM UI can also import a deployed REST API Service ("Import API from Boomi Platform").

## References

- `references/request_body.md`. Use when: writing a create or update body file, or reading a CAM error message. Holds endpoint, policy, package, plan, and key fields, allowed values, and misleading error messages.
