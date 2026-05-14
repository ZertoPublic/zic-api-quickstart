# 01 — Get a Keycloak token

Every other call in this repo starts here. You exchange your
appliance username + password for an OAuth bearer token (a JWT
issued by the ZIC appliance's embedded Keycloak), then attach that
token to every `/zic/api/v1/*` request.

## The endpoint

```
POST  https://<zic-host>/auth/realms/zerto/protocol/openid-connect/token

Content-Type: application/x-www-form-urlencoded

grant_type=password
scope=openid              ← required
client_id=zerto-client
username=<your-user>
password=<your-pass>
```

Success returns:

```json
{
  "access_token":       "eyJhbGciOiJSUzI1NiI...",
  "expires_in":         60,
  "refresh_token":      "...",
  "refresh_expires_in": 1800,
  "token_type":         "Bearer",
  "scope":              "openid profile email"
}
```

You hand the `access_token` back on every subsequent call as:

```
Authorization: Bearer eyJhbGciOiJSUzI1NiI...
```

## A note on the auth flow

The ZIC swagger declares the security scheme as OAuth 2.0 **implicit
flow** with the authorization endpoint
`/auth/realms/zerto/protocol/openid-connect/auth`. That's the flow
the interactive Swagger UI uses when you click "Authorize."

For scripted access, the **password grant** on the same Keycloak realm
is what works and what every Zerto v10 API client uses — it's how
both ZVM and ZCA scripts authenticate, and ZIC inherits the same
Keycloak setup. This script uses the password grant.

## Things that bite you the first time

- **`scope=openid` is required.** Without it Keycloak issues a token,
  but `/zic/api/v1/*` rejects it with 401.
- **Tokens expire fast.** `expires_in` is usually 60 seconds. For
  short scripts, re-authenticate at the start of each run. For
  long-running tools, use the `refresh_token` to get a new access
  token without re-prompting for the password.
- **Lab realms differ.** A production install uses `realm=zerto` and
  `client_id=zerto-client`. A lab/PoC install may use the built-in
  `master` realm with `client_id=admin-cli`. Try the production
  pair first.

## Run it

```bash
# bash
cd zic-aws/examples/01-get-token
cp ../../.env.example ../../.env   # first time only
$EDITOR ../../.env
./get-token.sh
```

```bash
# python
python3 get_token.py
```

```powershell
# powershell 7+
$env:ZIC_HOST = "10.10.1.69"
$env:ZIC_USERNAME = "zerto"
$env:ZIC_PASSWORD = "changeme"
./Get-Token.ps1
```

All three print the access token to stdout. To use it by hand:

```bash
TOKEN=$(./get-token.sh)
curl -k -H "Authorization: Bearer $TOKEN" https://10.10.1.69/zic/api/v1/vpgs
```
