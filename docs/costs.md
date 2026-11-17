# Costs

Rough monthly figures for a US region at on-demand prices, to show what drives the bill.
Prices change and differ by region: check the
[AWS Pricing Calculator](https://calculator.aws/) for current numbers.

| Item | Rough cost | Notes |
| --- | --- | --- |
| EC2 t3.medium (2 vCPU, 4 GB) | about $30 | Smallest size that runs the stack |
| EC2 t3.large (2 vCPU, 8 GB) | about $61 | Comfortable for running |
| EBS gp3, 20 GB root + 60 GB data | about $6.40 | $0.08 per GB-month |
| Public IPv4 address | about $3.65 | Charged for every public IPv4, Elastic or not |
| S3 Standard (sync on) | about $0.023 per GB | Plus old versions, which move to Glacier Instant Retrieval after 30 days |
| S3 requests (sync on) | cents | A sync with nothing new only lists the bucket |
| Data transfer out | first 100 GB free | Then about $0.09 per GB |

A default deployment without S3 is roughly **$40 a month**.

## Keeping it down

- **Stop the instance when you are not using it.** A stopped instance costs nothing for
  compute; you still pay for the volumes and the Elastic IP.
- **Run it only when you use it.** `enable_schedule = true` adds two EventBridge schedules
  that start the instance at 5pm and stop it at 9pm Pacific on weekdays (change the times
  with `schedule_start_cron`, `schedule_stop_cron` and `schedule_timezone`). That is about
  87 hours a month instead of 730, which brings a t3.medium from about $30 to under $4.
  Disk and the public IP still bill around the clock. The stack comes back by itself after
  each start; allow a few minutes. Agents and people must know the hours: nothing answers
  outside them. Set `BACKUP_SCHEDULE` in `.env` to a time inside the window, or the backup
  runs right after each start. To work outside the window, start the instance by hand; the next scheduled
  stop still applies.
- **Build big, run small.** The source build is the only heavy step. Changing the instance
  type takes a stop and a start, and the data volume keeps the built images. An hour on a
  t3.xlarge (4 vCPU, 16 GB) costs about $0.17; you can then go back to t3.medium.
- **Building on t3.medium works against upstream's advice.** It is below their stated
  minimum, so the build leans on swap, can take several hours and may fail when the linker
  runs out of memory. `scripts/bootstrap.sh` refuses unless RAM plus swap is at least 15 GB
  and 40 GB of disk is free, or you pass `--force`.
- **EBS volumes can grow but never shrink.** Start at 60 GB and grow if needed.
- **Savings Plans or Reserved Instances** cut the compute price if you run all month.
- **Backups accumulate.** Set `BACKUP_RETENTION_DAYS` in the upstream `.env` to prune local
  backups. With `SYNC_DELETE=false` the bucket keeps everything; add an expiration rule or
  set `SYNC_DELETE=true` if the bucket grows too large.
