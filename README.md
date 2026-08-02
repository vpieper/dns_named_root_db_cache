# BIND Root Files Auto-Updater (Debian 13)

A robust, fail-fast bash script to securely update BIND DNS root hints (`named.root`) and root cache (`db.cache`) from InterNIC. Designed specifically for Debian-based environments.

## Why This Script?
Standard `curl` cron one-liners often fail silently or overwrite live DNS configurations with corrupted files if the network drops or a web server serves an HTML error page. Furthermore, InterNIC's web servers currently serve an SSL certificate with a missing Subject Alternative Name (SAN) for their `www` subdomain, causing standard automated downloads to fail. 

This script solves these issues by providing:
* **Atomic Updates:** Downloads files to hidden temporary locations first. Live BIND files are only overwritten if the `curl` payload succeeds 100%.
* **SSL Workaround:** Safely bypasses the known InterNIC SAN certificate mismatch (`curl -k`) while ensuring the correct raw text files are retrieved instead of HTML redirects.
* **Debian Permission Handling:** Automatically adjusts strict `mktemp` permissions (`chmod 644`) before moving files into production, ensuring the unprivileged `bind` user can read them during an `rndc reload`.
* **Integrated Alerting:** Sends formatted success or failure emails directly to the administrator.

## Prerequisites
Ensure your Debian system has standard mail utilities installed for the alerting function:
```bash
apt install mailutils curl
```

## Installation

1. Clone or download `dns_root_update.sh` to your preferred directory (e.g., `/root/dns_named_root_db_cache/`).
2. Open the script and update the `ADMIN_EMAIL` variable with your actual email address.
3. Make the script executable:
```bash
chmod +x /root/dns_named_root_db_cache/dns_root_update.sh
```

## Usage & Automation

The script is designed to run silently in the background via cron, triggering an email only with the final status. Add the following to your root crontab (`crontab -e`) to run the update at 2:00 AM on the 1st of every month:

```text
# Update BIND root files and send status email
0 2 1 * * /root/dns_named_root_db_cache/dns_root_update.sh
```

## Error Handling
If a download fails or BIND refuses to reload, the script will immediately halt, preserve the existing production files to maintain DNS resolution, and email the administrator the exact error output.
