# S3 Log Archival Plan

## Logging Approach

Phase 1 uses two layers:

- short local OpenClaw host logs under `/tmp/openclaw`
- host logrotate policy for `/tmp/openclaw` and `/var/log/openclaw/*.log`
- short CloudWatch retention for quick troubleshooting
- daily S3 archival for cheap longer retention

This keeps the host simple and avoids running a separate log stack.

## Local Retention

Host logs use logrotate:

- daily rotation
- gzip compression
- `7` retained files for OpenClaw and cron job logs
- `3` retained files for temporary archive bundles under `/var/log/openclaw/archive`

This keeps host logs from growing unbounded between S3 uploads.

## CloudWatch Retention

The CloudWatch agent tails:

- OpenClaw host logs under `/tmp/openclaw/openclaw-*.log`
- `/var/log/messages`

Recommended retention:

- `7` days for system logs

## S3 Archive Flow

Nightly job:

1. Export recent OpenClaw host logs
2. Gzip the output
3. Upload to:

```text
s3://<archive-bucket>/<archive-prefix>/logs/YYYY/MM/DD/
```

4. Keep local archive files only for a short window

## S3 Lifecycle Recommendation

Set the S3 bucket lifecycle to:

- retain current objects for `90` days minimum
- transition to Glacier Instant Retrieval or Flexible Retrieval later if desired
- expire incomplete multipart uploads after `7` days

## Why Not a Managed Logging Stack

For Phase 1, CloudWatch plus S3 is enough:

- cheaper
- less operational surface
- fits the single-instance design
- easy to replace later when the app moves to larger container infrastructure
