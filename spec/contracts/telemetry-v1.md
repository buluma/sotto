# Sotto telemetry and local diagnostics contract

Remote analytics and crash-event transport are removed. Application and CLI
composition always select `NoOpTelemetryService`. There is no telemetry HTTP
client, timer, retry queue, endpoint, or environment override to enable uploads.
Typed event hooks remain injectable for local tests; they do not imply network
collection. Local logs and crash artifacts remain on-device unless explicitly
exported by the user. The legacy telemetry configuration key is inert.

Validation: `TelemetryServiceTests` and `CLITelemetryTests`, alongside retained
local crash/observability tests. Original GPL and third-party notices remain.
