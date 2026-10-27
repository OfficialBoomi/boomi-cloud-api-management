# CAM body fields

Fields, allowed values, and error messages for the JSON body files the scripts take.

## Contents

1. Update bodies
2. Endpoint fields
3. Processor (policy) shape
4. Package and plan fields
5. Applications and keys
6. OpenAPI import
7. Errors

## 1. Update bodies

- An update merges. Fields not sent keep their values.
- Update bodies carry scalar fields only. The scripts refuse `endpoints`, `plans`, `services`, and `methods`.
- Service and endpoint create print the object re-read with full fields.

## 2. Endpoint fields

Required on create: `name`, `requestPathAlias`, `trafficManagerDomain`.

| Field | Values and behavior |
|---|---|
| `requestAuthenticationType` | `apiKey`, `apiKeyAndSecret_SHA256`, `oauth`, `custom`. |
| | No `none`. Any unknown value maps to `custom`, which then 400s without `customRequestAuthenticationAdapter`. |
| | Omitted → `apiKey`. `oauth` needs OAuth enabled on the service. |
| `apiKeyValueLocations` | `request-parameters`, `request-header` (singular). `request-body`. `request-headers` fails with a misleading "is required" 400. |
| `apiKeyValueLocationKey` | Key field name. Default `api_key`. |
| `publicDomains`, `systemDomains` | The public domain must be on the area's domain whitelist. A backend host needs no whitelisting. |
| | Public domain + path must be unique in the area. |
| `connectionTimeoutForSystemDomainRequest` | Connect timeout, 2–7 s. Other values → 400. |
| `connectionTimeoutForSystemDomainResponse` | Read timeout, ≥2 s. SaaS maximum 120 s, then 504. |
| `systemDomainAuthentication` | Backend auth: `{"type":"httpBasic","username":..,"password":..}`. `null` clears it. |

## 3. Processor (policy) shape

Policies live in the endpoint's `processor` object. Write it with `cam-endpoint.sh update`.

- Fields: `adapter`, `preProcessEnabled`, `postProcessEnabled`, `preInputs`, `postInputs`.
- One processor: put its name or class in `adapter` directly.
- Several: `adapter` = `Mashery_Proxy_Processor_Chain`. List the classes comma-separated in `preInputs.processors` and `postInputs.processors`.
- A named policy such as CircuitBreaker takes its parameters in `preInputs` and `postInputs`.
- Clear: `{"adapter":"","preProcessEnabled":false,"postProcessEnabled":false,"preInputs":{},"postInputs":{}}`.
- `"processor": null` → 500. `"processor": {}` → 200 but changes nothing.
- Policy catalog: https://help.boomi.com/docs/Atomsphere/API%20Management/cam/cloud/ConnectorGuides/BoomiMasheryConnectors/Supported_policies

## 4. Package and plan fields

- Package: only `name` is required.
- `notifyDeveloperPeriod`: `minute`, `hour`, `day`, `week`, `month`. Omitted → `day`.
- `notifyDeveloperPeriod: "never"` → 400 "Property 'notifyDeveloperPeriod' is required". The message is misleading.
- Plan: only `name` is required.
- Plan limits: `qpsLimitCeiling`, `rateLimitCeiling`, `rateLimitPeriod`, `maxNumKeysAllowed`, `numKeysBeforeReview`.
- Plan key provisioning: `adminKeyProvisioningEnabled`, `selfServiceKeyProvisioningEnabled`.
- Plan `status` and `selfServiceKeyProvisioningEnabled` are ignored on write.
- Plan `services[]` shape: `[{"id":SID,"endpoints":[{"id":EID}]}]`. Accepted inline on plan create.

## 5. Applications and keys

- An application belongs to an existing member. `cam-app.sh create` takes the member's username.
- New applications are always `draft`. The API cannot change that.
- Apps with active keys also read `draft`. Draft does not block a key.
- `cam-key.sh create` has CAM generate the key.
- A new key can land in `waiting` even when `active` is sent. Run `cam-key.sh enable`.
- A developer email fires on key create.
- A second key for the same application, package, and plan → 400 "Duplicate Object".
- Key status values: `waiting`, `active`, `disabled`.

## 6. OpenAPI import

- Each endpoint is named `<title>.<path>`.
- Its `requestPathAlias` includes the server URL base path. A server of `https://host/anything` gives `/anything/hello`. Edit the alias after import if that is not wanted.

## 7. Errors

- Shape: `{"errorCode":..,"errorMessage":".."}`. Some errors add `errors` or `property` and `message`.
- The import transform returns only `{"errorMessage":..}`.
- Misleading messages:
  - An unknown enum value reads as "Property ... is required".
  - `requestAuthenticationType` typos read as a missing `customRequestAuthenticationAdapter`.
  - A consumer call before any plan grants the endpoint → 403 "Developer Inactive".
  - A consumer call with no key also → 403 "Developer Inactive". It does not say the key is missing.
