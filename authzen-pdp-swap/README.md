# Swapping the PDP behind an unchanged PEP (AuthZEN)

Sends the same AuthZEN evaluation request to a native implementation (Keycloak) and to
an adapter in front of a general-purpose engine (OPA + proxy), and compares what comes
back — decisions, discovery, batch, authentication, and input validation.

## Related article

- ja: https://portfolio-site.iganin.workers.dev/ja/articles/authzen-pdp-swap/
- en: https://portfolio-site.iganin.workers.dev/en/articles/authzen-pdp-swap/

## Environment

| What          | Version                                                |
| ------------- | ------------------------------------------------------ |
| Docker        | 24.0.5                                                 |
| Keycloak      | 26.7.2 (quay.io, `--features=authzen`)                 |
| OPA           | 1.9.0                                                  |
| Node.js       | 22 (alpine image, for both proxies)                    |
| authzen-proxy | open-policy-agent/contrib (sparse clone into `vendor/`) |

## Layout

- `compose.yml` — Keycloak, OPA, the contrib proxy (host port 3030),
  and `hardened-proxy` (host port 3031).
- `configure-keycloak.sh` — builds the `demo` realm through the Admin REST API:
  users alice (role `reader`) and bob, resource `123` of type `document`,
  scope `can_read`, and the permission that ties them together.
  Also adds the audience mapper that introspection needs.
- `policy.rego` — the same decision expressed for OPA. Both PDPs answer
  the same six requests identically.
- `evaluate.sh` — sends one request to Keycloak. The endpoint comes from discovery.
- `compare.sh` — the two-way comparison (Keycloak vs. contrib proxy).
- `compare3.sh` — the three-way comparison (adds `hardened-proxy`).
- `probe-context.sh` — adds a Regex policy on the identity attribute `department`
  and checks whether `subject.properties` in the request actually changes the decision.
  Also checks `X-Request-ID` propagation.
- `hardened-proxy/server.mjs` — 169 lines, zero dependencies. Adds input validation,
  token verification by introspection, discovery, and batch to the contrib proxy's
  behaviour. The decision itself is unchanged: it looks at the same OPA and the same Rego.

## How to run

Copy `.env.example` to `.env` first. The contrib proxy is not vendored here; fetch it:

```sh
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/open-policy-agent/contrib.git vendor/contrib
cd vendor/contrib && git sparse-checkout set authzen/authzen-proxy && cd ../..
```

```sh
cp .env.example .env
docker compose up -d
./configure-keycloak.sh   # create the demo realm
./compare.sh              # same request, two PDPs
./compare3.sh             # same request, three PDPs
./probe-context.sh        # request-side properties, X-Request-ID
```

`configure-keycloak.sh` and `probe-context.sh` are not idempotent — they create
realm objects. Run `docker compose down -v` before re-running them from scratch.

## What came out

The decision travels. Nothing around it does.

The same six requests (permit, deny, misspelled subject, undefined action, nonexistent
resource, wrong type) produced identical answers from both PDPs. The only thing the PEP
changed was the destination URL.

Everything else diverged, and in the unsafe direction: the contrib proxy answers
`{"decision":true}` to a request that omits a REQUIRED field, and to a request with no
credentials at all, while Keycloak answers 400 and 401. It has no discovery endpoint and
no batch endpoint.

`hardened-proxy` closes all four gaps in 169 dependency-free lines, and then matches
Keycloak on every row. But closing the authentication gap took vendor-specific Keycloak
configuration: pinning the issuer, and adding an audience mapper so that the introspecting
client appears in the token's `aud`. Until then, introspection answered `{"active":false}`
for a valid token and said nothing about why.
