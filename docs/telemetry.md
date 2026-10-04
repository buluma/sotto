# Sotto diagnostics

Sotto has no remote telemetry transport. The former HTTP endpoint, batching,
retry queue, timers, URLSession uploader, and environment enablement policy
have been removed. GUI and CLI configure `NoOpTelemetryService`; no opt-out or
crash telemetry is uploaded. Legacy event schemas and injectable hooks remain
for local service tests and diagnostic correlation.

Local OSLog and crash diagnostic files remain on-device. Explicit exports and
feedback are separate user actions. Optional AI providers, media/model download, and gated sharing retain their own network boundaries.

`config telemetry` is a legacy compatibility preference only. Neither it nor
`SOTTO_TELEMETRY=1` enables network telemetry.
