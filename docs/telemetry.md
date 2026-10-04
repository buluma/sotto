# Sotto diagnostics

Sotto has no remote telemetry transport. The former HTTP endpoint, batching,
retry queue, timers, URLSession uploader, and environment enablement policy
have been removed. GUI and CLI configure `NoOpTelemetryService`; no opt-out or
crash telemetry is uploaded. Legacy event schemas and injectable hooks remain
for local service tests and diagnostic correlation.

Local OSLog and crash diagnostic files remain on-device. Explicit exports remain
user actions. Upstream feedback and hosted sharing transports are removed.
Optional AI providers and media/model downloads retain their own network boundaries.

`config telemetry` is a legacy compatibility preference only. Neither it nor
`SOTTO_TELEMETRY=1` enables network telemetry.
