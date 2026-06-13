<div align="center">

# VICIdial Custom Extensions

[![ViciBox](https://img.shields.io/badge/ViciBox-11.0.1-blue?style=for-the-badge&logo=linux)](https://www.vicibox.com/)
[![VICIdial](https://img.shields.io/badge/VICIdial-2.14--48-orange?style=for-the-badge)](https://www.vicidial.org/)
[![PHP](https://img.shields.io/badge/PHP-7.x%20%2F%208.x-777BB4?style=for-the-badge&logo=php)](https://www.php.net/)
[![MariaDB](https://img.shields.io/badge/MariaDB-10.x+-003545?style=for-the-badge&logo=mariadb)](https://mariadb.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green?style=for-the-badge)](LICENSE)

**Three production-ready, non-destructive extensions for VICIdial — each one installs with a single script.**

</div>

---

## What's Included

| # | Extension | What It Does | Script |
|---|-----------|--------------|--------|
| 1 | [**Real-Time Dial Level Control**](#1-real-time-dial-level-control) | Adds a campaign selector + dial level picker directly on the Real-Time report screen | `Realtime-dial-level.sh` |
| 2 | [**Custom Lead List Columns**](#2-custom-lead-list-id--name-columns) | Shows LIST ID and LIST NAME in the live agent stats view | `add-custom-lead-list_name.sh` |
| 3 | [**Recording Portal**](#3-vicidial-recording-portal) | Standalone web portal to search, play, and download call recordings | `vicidial_self_rec_portal_setup.sh` |

> All patches create timestamped backups before touching any file, validate PHP syntax before deploying, and are safe to re-run after VICIdial upgrades.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          VICIdial Server                                │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Apache / Web Layer                                              │   │
│  │                                                                  │   │
│  │  /vicidial/                        /recording/                   │   │
│  │  ┌─────────────────────┐           ┌──────────────────────────┐  │   │
│  │  │  realtime_report.php│           │  Recording Portal        │  │   │
│  │  │  [PATCHED]          │           │  (login · search · play) │  │   │
│  │  │   + Dial Level Row  │           └────────────┬─────────────┘  │   │
│  │  │   + cdl_api.php     │                        │                │   │
│  │  └──────────┬──────────┘                        │                │   │
│  │             │                                   │                │   │
│  │  AST_timeonVDADall.php                          │                │   │
│  │  [PATCHED]                                      │                │   │
│  │   + LIST ID column                              │                │   │
│  │   + LIST NAME column                            │                │   │
│  └─────────────┼───────────────────────────────────┼────────────────┘   │
│                │                                   │                    │
│  ┌─────────────▼───────────────────────────────────▼────────────────┐   │
│  │  MariaDB                                                          │   │
│  │  vicidial DB ──── vicidial_campaigns ──── vicidial_users          │   │
│  │  vicidial DB ──── vicidial_live_agents ── vicidial_list           │   │
│  │  recording_portal DB ── rec_file_index ── rec_audit               │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Cron (low-priority)                                               │  │
│  │  03:30 UTC  → Full recording index (daily)                         │  │
│  │  */30 UTC   → Incremental index  (03:45–09:30 UTC / IST business)  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Global Requirements

- VICIdial installed and fully operational
- Root or `sudo` access on the VICIdial/ViciBox server
- Python 3 (pre-installed on ViciBox)
- Web root: `/srv/www/htdocs/vicidial/` (ViciBox/SUSE) **or** `/var/www/html/vicidial/` (Debian/Ubuntu/CentOS)

---

## 1. Real-Time Dial Level Control

> **Files:** `cdl_api.php` · `Realtime-dial-level.sh`

Adds a **campaign selector** and **dial level control** row directly on the Real-Time Main Report page — no need to navigate into Campaign Settings just to change the dial level.

### How It Looks

```
┌────────────────────────────────────────────────────────────────────────┐
│  Real-Time Main Report                                        [LIVE ●] │
├────────────────────────────────────────────────────────────────────────┤
│  Select Campaign: [ CBS-OH-Outbound (370703) ▾ ]                       │
│  Select Dial Level: [ 2.0 ▾ ]   [ Set Dial Level ]  ✔ Dial level set  │
├────────────────────────────────────────────────────────────────────────┤
│  AGENT NAME    STATUS    CAMPAIGN    PHONE NUMBER    ...                │
│  ...                                                                   │
└────────────────────────────────────────────────────────────────────────┘
```

### Features

| Feature | Detail |
|---------|--------|
| **Campaign dropdown** | Lists all campaigns the user is permitted to access (respects `allowed_campaigns` per user group) |
| **Live dial level** | Reads and displays the current live value from `vicidial_campaigns.auto_dial_level` |
| **Set Dial Level** | Writes the chosen level instantly to the DB; logs the change to `vicidial_admin_log` |
| **Auto-sync** | Selecting a campaign in "Choose Report Display Options" auto-syncs the control row to that campaign |
| **Permission-aware** | Users without `modify_campaigns = Y` **and** `user_level > 6` see controls as read-only |
| **Audit trail** | Every write logged with timestamp, user, IP, and SQL executed |
| **Master DB writes** | `cdl_api.php` always connects to the master DB — works correctly on slave-report setups |

### Data Flow

```
Browser                    cdl_api.php                   MariaDB (master)
   │                            │                               │
   │─── GET ?action=campaigns ─►│                               │
   │                            │── SELECT campaigns ──────────►│
   │                            │◄─ campaign rows ──────────────│
   │◄── JSON [{id, name}] ──────│                               │
   │                            │                               │
   │─── GET ?action=set ────────►│                               │
   │    &campaign=X&level=2.5   │── UPDATE auto_dial_level ────►│
   │                            │── INSERT vicidial_admin_log ─►│
   │◄── {"ok":true} ────────────│                               │
```

### Installation

#### Step 1 — Deploy the API file

```bash
# ViciBox / SUSE
cp cdl_api.php /srv/www/htdocs/vicidial/
chown wwwrun:www /srv/www/htdocs/vicidial/cdl_api.php
chmod 644 /srv/www/htdocs/vicidial/cdl_api.php

# Debian / Ubuntu / CentOS
cp cdl_api.php /var/www/html/vicidial/
chown www-data:www-data /var/www/html/vicidial/cdl_api.php
chmod 644 /var/www/html/vicidial/cdl_api.php
```

#### Step 2 — Test the API

While logged into VICIdial in your browser, run (replace the placeholders):

```bash
curl -u ADMINUSER:PASSWORD \
  'https://YOUR-SERVER/vicidial/cdl_api.php?cdl_action=campaigns&cdl_u=ADMINUSER'
```

**Expected response:**
```json
{"ok":true,"can_write":true,"campaigns":[{"campaign_id":"001","campaign_name":"My Campaign"}],"count":5}
```

> Do not proceed to Step 3 until the API returns valid JSON.

#### Step 3 — Run the patch script

```bash
chmod +x Realtime-dial-level.sh
./Realtime-dial-level.sh
```

The script automatically:
1. Detects `realtime_report.php` in common web root paths
2. Creates a timestamped backup (e.g. `realtime_report.php.bak.20260612-091500`)
3. Strips any previously applied version of this patch
4. Injects the control row HTML + AJAX JavaScript
5. Validates PHP syntax — aborts if the syntax check fails
6. Installs the patched file in-place (preserving owner and permissions)

To specify the path manually:
```bash
./Realtime-dial-level.sh /srv/www/htdocs/vicidial/realtime_report.php
```

#### Step 4 — Verify

Open the Real-Time report and hard-refresh (**Ctrl+F5**). The control row should appear above the carrier stats.

### Usage

1. Select a campaign from the dropdown
2. Choose a dial level (1.0–12.0 in 0.5 steps)
3. Click **Set Dial Level** — the change is live immediately

**Auto-sync tip:** Open "Choose Report Display Options", select a specific campaign, click SUBMIT — the control row automatically switches to that campaign and loads its current dial level.

> **Dial method note:** Dial level only affects `RATIO` campaigns. It has no effect on `INBOUND_MAN` or `MANUAL` campaigns. On `ADAPT_*` methods VICIdial recomputes the level automatically and may override your setting.

### After a VICIdial Upgrade

Upgrades overwrite `realtime_report.php`. Re-run the patch — `cdl_api.php` is unaffected:

```bash
./Realtime-dial-level.sh
```

### Rollback

The patch script prints the exact restore command on every run:

```bash
cp -p /srv/www/htdocs/vicidial/realtime_report.php.bak.YYYYMMDD-HHMMSS \
      /srv/www/htdocs/vicidial/realtime_report.php

# Remove the API file if desired
rm /srv/www/htdocs/vicidial/cdl_api.php
```

### API Reference

**Endpoint:** `GET /vicidial/cdl_api.php`

| Parameter | Values | Required For |
|-----------|--------|-------------|
| `cdl_action` | `campaigns` · `get` · `set` | All requests |
| `cdl_u` | VICIdial username | All requests |
| `cdl_campaign` | Campaign ID string | `get`, `set` |
| `cdl_dial_level` | `1.0` – `20.0` | `set` |

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `campaigns: []` | Column named differently | Run `DESCRIBE vicidial_campaigns` — script uses `auto_dial_level` |
| `{"ok":false,"err":"auth_failed"}` | User not found or inactive | Verify user exists and `active='Y'` in `vicidial_users` |
| `{"ok":false,"err":"db_connect_failed"}` | Wrong DB credentials | Check `VARDB_user` / `VARDB_pass` in `/etc/astguiclient.conf` |
| Dropdown shows `err:http_404` | API file not in web root | Confirm `cdl_api.php` is in the same directory as `realtime_report.php` |
| Set Dial Level does nothing | Campaign is `INBOUND_MAN` or `MANUAL` | Expected — dial level has no effect on those dial methods |
| Control row missing after upgrade | VICIdial upgrade overwrote the file | Re-run `Realtime-dial-level.sh` |

---

## 2. Custom Lead List ID / Name Columns

> **Files:** `add-custom-lead-list_name.sh` · `AST_timeonVDADall_patched.php`

Adds **LIST ID** and **LIST NAME** columns to VICIdial's live agent stats screen (`AST_timeonVDADall.php`), giving supervisors instant visibility into which list each agent is currently working — without leaving the monitoring screen.

### How It Looks

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  Agent Time on VICIdial — Real-Time                                           │
├──────────────┬──────────┬───────────┬─────────────────┬──────────┬────────────┤
│  AGENT NAME  │  STATUS  │  CAMPAIGN │  PHONE NUMBER   │ LIST ID  │ LIST NAME  │
├──────────────┼──────────┼───────────┼─────────────────┼──────────┼────────────┤
│  John Smith  │  INCALL  │  SALES-01 │  +1-555-123-4567│  105032  │ Hot Leads  │
│  Jane Doe    │  READY   │  SALES-01 │                 │  105033  │ Warm Leads │
└──────────────┴──────────┴───────────┴─────────────────┴──────────┴────────────┘
```

### Features

| Feature | Detail |
|---------|--------|
| **LIST ID column** | Shows the numeric list ID for the lead the agent is currently handling |
| **LIST NAME column** | Human-readable list name pulled from `vicidial_lists` |
| **Non-destructive** | All original columns and report behaviour are fully preserved |
| **Idempotent** | Script detects if patch is already applied and skips without making changes |
| **Cross-platform** | Works on ViciBox (OpenSUSE Leap 15), CentOS 7/8, RHEL, Ubuntu |

### How It Works

```
AST_timeonVDADall.php (original)         AST_timeonVDADall.php (patched)
┌───────────────────────────────┐        ┌───────────────────────────────────────┐
│  SELECT agent, status,        │        │  SELECT agent, status,                │
│    campaign, phone            │  ───►  │    campaign, phone,                   │
│  FROM vicidial_live_agents    │        │    vl.list_id,          ◄─ NEW        │
└───────────────────────────────┘        │    vll.list_name        ◄─ NEW        │
                                         │  FROM vicidial_live_agents vl         │
                                         │  LEFT JOIN vicidial_lists vll         │
                                         │    ON vl.list_id = vll.list_id        │
                                         └───────────────────────────────────────┘
```

### Installation

```bash
chmod +x add-custom-lead-list_name.sh
./add-custom-lead-list_name.sh
```

The script automatically:
1. Detects the live `AST_timeonVDADall.php` across all supported distro paths
2. Creates a timestamped backup before touching anything
3. Locates the patched source file (`AST_timeonVDADall_patched.php`)
4. Validates PHP syntax on the patched file
5. Deploys the patch in-place, preserving the file's original owner and permissions
6. Exits cleanly if the patch is already applied (idempotent)

### After a VICIdial Upgrade

Upgrades overwrite `AST_timeonVDADall.php`. Re-run the installer:

```bash
./add-custom-lead-list_name.sh
```

The script detects no existing patch and applies cleanly from the bundled patched file.

### Rollback

```bash
# The script prints the restore path on every run — example:
cp -p /srv/www/htdocs/vicidial/AST_timeonVDADall.php.bak.YYYYMMDD-HHMMSS \
      /srv/www/htdocs/vicidial/AST_timeonVDADall.php
```

---

## 3. VICIdial Recording Portal

> **File:** `vicidial_self_rec_portal_setup.sh` (899 lines — complete full-stack installer)

A **standalone web portal** for searching, playing, and downloading VICIdial call recordings — accessible at `https://<your-server>/recording/`. Designed for zero impact on the VICIdial server during business hours.

### Portal Interface

```
┌──────────────────────────────────────────────────────────────────────────┐
│  🎙  VICIdial Recording Portal                          [Logout]         │
├──────────────────────────────────────────────────────────────────────────┤
│  Phone Number  [ ____________ ]   Agent    [ ____________ ]             │
│  Campaign      [ ____________ ]   List ID  [ ____________ ]             │
│  Date From     [ YYYY-MM-DD  ]   Date To  [ YYYY-MM-DD  ]              │
│                                            [ 🔍 Search ]               │
├──────────────────────────────────────────────────────────────────────────┤
│  PHONE          NAME         DATE/TIME           AGENT    DUR   SIZE    │
│  555-123-4567   John Smith   2026-06-12 09:15    jdoe     3:42  2.1 MB  │
│  ▶ ────────────────────────────────────────── 01:23 / 03:42            │
│  [ ▶ Play ] [ ⬇ Download ]                                             │
├──────────────────────────────────────────────────────────────────────────┤
│  Total recordings: 14,823  │  Last sync: 2026-06-13 03:30  │ [Refresh] │
└──────────────────────────────────────────────────────────────────────────┘
```

### Architecture

```
                     ┌─────────────────────────────────┐
                     │   Browser (Single-Page App)      │
                     │   Dark-themed login + search UI  │
                     └────────────────┬────────────────┘
                                      │ HTTPS
                     ┌────────────────▼────────────────┐
                     │   PHP Backend (/recording/)      │
                     │                                  │
                     │  ┌──────────┐  ┌─────────────┐  │
                     │  │  Auth    │  │  Search API │  │
                     │  │  Login   │  │  Streaming  │  │
                     │  │  Session │  │  Download   │  │
                     │  └──────────┘  └─────────────┘  │
                     └────────────────┬────────────────┘
                                      │
              ┌───────────────────────┴──────────────────────┐
              │                                              │
┌─────────────▼────────────┐              ┌─────────────────▼──────────────┐
│  recording_portal DB     │              │  VICIdial master DB             │
│  ┌────────────────────┐  │              │  vicidial_campaigns             │
│  │  rec_file_index    │  │              │  vicidial_live_agents           │
│  │  rec_metadata_shadow│ │              │  vicidial_list                  │
│  │  rec_users         │  │              └────────────────────────────────┘
│  │  rec_sessions      │  │
│  │  rec_audit         │  │
│  └────────────────────┘  │
└──────────────────────────┘
              ▲
              │ cron (low priority)
┌─────────────┴──────────────────────────────────────────────────────┐
│  Python Indexer                                                     │
│  Scans /var/spool/asterisk/monitorDONE/MP3/                        │
│  Extracts metadata from filenames + VICIdial DB                    │
│  Builds MySQL indexes for <200ms search queries                    │
└────────────────────────────────────────────────────────────────────┘
```

### Indexing Schedule

| Cron Job | UTC Time | IST Equivalent | Purpose |
|----------|----------|----------------|---------|
| Full index | 03:30 daily | 09:00 IST | Complete re-scan of all recordings |
| Incremental | Every 30 min, 03:45–09:30 | 09:15–15:00 IST | Picks up new recordings during business hours |

All cron jobs run with `nice -n 19 ionice -c 3` (absolute lowest CPU and I/O priority) so they never impact VICIdial during business hours.

### Features

| Feature | Detail |
|---------|--------|
| **Full-text search** | Search by phone, agent login, campaign ID, list ID, or date range |
| **Inline audio player** | Seek-bar player directly in the results table — no download required |
| **Streaming playback** | HTTP range requests supported — seek anywhere in large files instantly |
| **Download** | Per-recording download button |
| **Session security** | HTTPOnly cookies · SAMESITE=Strict · password hashing |
| **Access audit log** | Every play and download logged to `rec_audit` |
| **Auto-poll** | UI refreshes stats every 10 seconds only when the browser tab is active |
| **Clean install** | Setup script removes any previous portal install before deploying |

### Database Schema

```
recording_portal database
│
├── rec_file_index          ← Core table
│   ├── id (PK)
│   ├── filename
│   ├── phone_number        ← indexed
│   ├── agent_login         ← indexed
│   ├── campaign_id         ← indexed
│   ├── list_id             ← indexed
│   ├── recording_date      ← indexed
│   ├── duration_seconds
│   └── file_size_bytes
│
├── rec_metadata_shadow     ← Lead info cache from VICIdial DB
│   ├── phone_number (PK)
│   ├── first_name
│   ├── last_name
│   └── list_id
│
├── rec_users               ← Portal authentication
│   ├── username (PK)
│   ├── password_hash
│   └── created_at
│
├── rec_sessions            ← Active session tokens
│   ├── token (PK)
│   ├── username
│   └── expires_at
│
└── rec_audit               ← Access log
    ├── id (PK)
    ├── username
    ├── action (play/download)
    ├── filename
    └── accessed_at
```

### Installation

> **Warning:** The setup script removes any previous recording portal installation (files, database, cron jobs) before deploying. Safe to re-run.

```bash
chmod +x vicidial_self_rec_portal_setup.sh
./vicidial_self_rec_portal_setup.sh
```

The script automatically:
1. Reads MySQL credentials from `/etc/astguiclient.conf` (no manual DB setup needed)
2. Auto-detects the web root (`/var/www/html/` or `/srv/www/htdocs/`)
3. Drops and recreates the `recording_portal` database with proper indexes
4. Deploys the PHP backend and single-page frontend to `/recording/`
5. Configures an Apache virtual host entry
6. Installs a `systemd` unit for manual index runs
7. Configures cron jobs for scheduled indexing
8. Creates the default admin account
9. Runs an initial background index at the lowest system priority

### After Installation

**Access the portal:**
```
https://<your-server>/recording/
```

**Default credentials:**
| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `RecAdmin@2025` |

> **Change the default password immediately after first login.**

**Trigger a manual index run:**
```bash
systemctl start vicidial-recording-index
```

**Check indexer logs:**
```bash
journalctl -u vicidial-recording-index --no-pager
```

**Check cron schedule:**
```bash
crontab -l | grep recording
```

### Recording Source Directory

The indexer scans:
```
/var/spool/asterisk/monitorDONE/MP3/
```

Ensure this path exists and recordings are landing there before running the initial index. If your recordings are stored elsewhere, update the path in the installed indexer script.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Portal returns 404 | Apache vhost not activated | Check Apache error log; verify `/recording/` alias in vhost config |
| Login fails with correct credentials | Session cookie blocked | Ensure HTTPS is active — SAMESITE=Strict cookies require a secure context |
| No recordings found after install | Indexer hasn't run yet | Run `systemctl start vicidial-recording-index` to force an immediate index |
| Indexer finds 0 files | Wrong recording directory | Verify files exist in `/var/spool/asterisk/monitorDONE/MP3/` |
| Search returns no results | DB empty | Check `SELECT COUNT(*) FROM recording_portal.rec_file_index` after indexer run |
| `db_connect_failed` in PHP logs | Credentials issue | Verify `/etc/astguiclient.conf` has correct `VARDB_user` / `VARDB_pass` |

---

## Global Compatibility

| Component | Supported Versions |
|-----------|--------------------|
| ViciBox | 11.0.1 (tested) |
| VICIdial | 2.14-48 build 231115-1646 (tested); should work on 2.14.x generally |
| PHP | 7.x / 8.x |
| MariaDB / MySQL | 10.x+ |
| Apache | 2.4+ |
| Linux Distros | OpenSUSE Leap 15 · CentOS 7/8 · RHEL · Ubuntu · Debian |
| Python | 3.x (standard on ViciBox) |

---

## Security Notes

- **Authentication:** All portal and API requests validated against `vicidial_users` on every call — no external session tokens
- **Permission gates:** Dial level writes require both `modify_campaigns = Y` **and** `user_level > 6`
- **SQL injection prevention:** All inputs parameterised via PDO prepared statements; campaign IDs stripped to `[a-zA-Z0-9_-]` before any query
- **Audit logging:** All dial level changes logged to `vicidial_admin_log`; all portal plays/downloads logged to `rec_audit`
- **Cookie security:** Recording portal uses HTTPOnly + SAMESITE=Strict session cookies
- **Read-only access:** `cdl_api.php` allows read (`campaigns`, `get`) without write permission; write (`set`) is separately gated

---

## File Reference

```
ViciBox-Custom-Dev/
├── cdl_api.php                        API endpoint for campaign dial level read/write
├── Realtime-dial-level.sh             Patcher for realtime_report.php
├── AST_timeonVDADall_patched.php      Pre-patched agent stats file (LIST ID + LIST NAME)
├── add-custom-lead-list_name.sh       Installer for the LIST ID/NAME patch
├── vicidial_self_rec_portal_setup.sh  Full-stack installer for the Recording Portal
└── LICENSE                            Apache 2.0
```

---

*Built for the Beltalk / VICIdial team. Maintained by the infrastructure group.*
