# Real provider API fixtures

These pinned specifications come from official provider repositories and are used only for deterministic parser and generator tests. Tests must never call the servers declared inside them.

- `sumup_provider_api.yaml`: primary OpenAPI 3.0 end-to-end fixture.
- `adyen_provider_api.yaml`: payout-focused OpenAPI 3.1 fixture with complex schemas.
- `paypal_provider_api.yaml`: official OpenAPI 3.0 JSON converted deterministically to YAML.

Each `<provider>_examples.json` contains the upstream OpenAPI `example`/`examples` nodes together with their JSON Pointer `source_path`. These files are extracted data, not hand-written expected generator output.

`manifest.yml` records provenance, upstream commit, license, transformation, and SHA-256. Do not update a fixture from a moving branch: select a commit, review upstream changes, regenerate the checksum, and update the manifest in the same change.

These are real specifications and may contain documentation examples that resemble credentials or personal data. Treat every example as untrusted test input; generated project fixtures must replace it with synthetic values.

Parser note: the SumUp document contains YAML timestamps. Safe loading may allow only the standard scalar classes required for OpenAPI data (for example `Date`/`Time`), while aliases and arbitrary object tags remain disabled.
