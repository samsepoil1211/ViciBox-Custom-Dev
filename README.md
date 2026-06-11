# VICIdial Real-Time Campaign & Dial Level Control

A non-destructive patch for VICIdial's `realtime_report.php` that adds a **Campaign selector** and **Dial Level control** directly on the Real-Time Main Report screen — no need to enter the campaign settings page to change the dial level.

> Tested on **ViciBox 11.0.1** · VICIdial **2.14-48** (Build 231115-1646) · MariaDB

---

## What it does

| Feature | Detail |
|---|---|
| **Campaign dropdown** | Lists all campaigns the logged-in user is allowed to see (respects `allowed_campaigns` per user group) |
| **Dial Level selector** | Shows the current live dial level for the selected campaign; changing it writes to the DB instantly |
| **Set Dial Level** | Writes the chosen level to `vicidial_campaigns.auto_dial_level` and logs the change to `vicidial_admin_log` |
| **Auto-sync** | When admin picks a campaign in "Choose Report Display Options" and clicks SUBMIT, the control row automatically switches to that campaign and loads its dial level |
| **Permission-aware** | Only users with `modify_campaigns = Y` and `user_level > 6` can write; others see the controls as read-only |

The rest of the Real-Time report (agent rows, carrier stats, live counters) is completely unchanged and keeps refreshing normally.

---

## Files

```
realtime_report.php          ← patched in-place on your server (not distributed here)
cdl_api.php                  ← new standalone API file, copy to VICIdial web root
patch_realtime_final.sh      ← applies the patch to realtime_report.php
```

> **`cdl_api.php`** handles all campaign reads and dial-level writes. It connects directly to the master DB via `/etc/astguiclient.conf` so it always works correctly on slave-report setups.

---

## Requirements

- VICIdial installed and working
- Root or sudo access to the VICIdial server
- Python 3 on the server (standard on ViciBox) — used by the patch script for injection
- The web root directory containing `realtime_report.php` (typically `/srv/www/htdocs/vicidial/` on ViciBox / SUSE, or `/var/www/html/vicidial/` on Debian/Ubuntu)

---

## Installation

### Step 1 — Copy `cdl_api.php` to the server

Upload `cdl_api.php` to your server and place it in the VICIdial web root:

```bash
cp cdl_api.php /srv/www/htdocs/vicidial/
chown wwwrun:www /srv/www/htdocs/vicidial/cdl_api.php
chmod 644 /srv/www/htdocs/vicidial/cdl_api.php
```

> For Debian/Ubuntu replace `wwwrun:www` with `www-data:www-data` and the path with `/var/www/html/vicidial/`.

### Step 2 — Test the API before patching anything

While logged into VICIdial in your browser, run this from the server (replace credentials):

```bash
curl -u ADMINUSER:PASSWORD \
  'https://YOUR-SERVER/vicidial/cdl_api.php?cdl_action=campaigns&cdl_u=ADMINUSER'
```

Expected response — a JSON array of your campaigns:

```json
{"ok":true,"can_write":true,"campaigns":[{"campaign_id":"001","campaign_name":"..."}],"count":5}
```

If you get `{"ok":false,...}` — see [Troubleshooting](#troubleshooting) below. Do not proceed until this returns valid JSON.

### Step 3 — Run the patch script

Upload `patch_realtime_final.sh` to the server, then:

```bash
chmod +x patch_realtime_final.sh
./patch_realtime_final.sh
```

The script will:
1. Auto-detect `realtime_report.php` in the common web root paths
2. Create a timestamped backup (e.g. `realtime_report.php.bak.20260611-151200`)
3. Strip any previously applied versions of this patch
4. Inject the control row and sync hook
5. Run `php -l` syntax check — aborts without installing if it fails
6. Install the patched file in-place (preserving owner and permissions)

To pass the path manually:

```bash
./patch_realtime_final.sh /srv/www/htdocs/vicidial/realtime_report.php
```

### Step 4 — Verify

Open the Real-Time report and hard-refresh (**Ctrl+F5**). The control row appears above the carrier stats:

```
Select Campaign: [CBS-OH-Outbound (370703) ▾]   Select Dial Level: [2.0 ▾]   [Set Dial Level]
```

---

## Usage

**Change dial level for a campaign:**
1. Select the campaign from the dropdown
2. Choose the new dial level (1.0 – 12.0 in 0.5 steps)
3. Click **Set Dial Level** — confirmation message appears and the change is live immediately

**Campaign sync:**
Open "Choose Report Display Options", select a single specific campaign, click **SUBMIT** — the control row automatically switches to that campaign and loads its current dial level. You don't need to navigate both selectors separately.

> **Note on dial methods:** Dial level only affects dialing behaviour on campaigns with `dial_method = RATIO`. On `INBOUND_MAN` or `MANUAL` campaigns the level has no effect on call delivery. On `ADAPT_*` methods, VICIdial recomputes the level automatically and may override your setting.

---

## Rollback

Every run of the patch script prints a restore command. To undo at any time:

```bash
cp -p /srv/www/htdocs/vicidial/realtime_report.php.bak.YYYYMMDD-HHMMSS \
      /srv/www/htdocs/vicidial/realtime_report.php
```

To remove `cdl_api.php`:

```bash
rm /srv/www/htdocs/vicidial/cdl_api.php
```

---

## After a VICIdial upgrade

Upgrades overwrite `realtime_report.php`. Re-run the patch script after any upgrade — `cdl_api.php` is unaffected and does not need to be re-deployed.

```bash
./patch_realtime_final.sh
```

The script detects no existing patch and applies cleanly.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `campaigns:[]` in curl output | Column name mismatch (`dial_level` vs `auto_dial_level`) | Confirm with `DESCRIBE vicidial_campaigns` — `cdl_api.php` uses `auto_dial_level` |
| `{"ok":false,"err":"auth_failed"}` | Username not found or user inactive | Confirm user exists and `active='Y'` in `vicidial_users` |
| `{"ok":false,"err":"db_connect_failed"}` | Wrong DB credentials in `/etc/astguiclient.conf` | Check `VARDB_user` and `VARDB_pass` in the conf file |
| Dropdown shows `err:http_404` | `cdl_api.php` not in the web root | Confirm the file is in the same directory as `realtime_report.php` |
| Set Dial Level does nothing | Campaign uses `INBOUND_MAN` or `MANUAL` dial method | Expected — dial level has no effect on those methods |
| Control row missing after upgrade | VICIdial upgrade overwrote `realtime_report.php` | Re-run `patch_realtime_final.sh` |
| Script error on install | Old version of patch still present | Script strips old blocks automatically — just re-run |

---

## Security notes

- `cdl_api.php` verifies the `cdl_u` username against `vicidial_users` on every request — no session token or HTTP Basic re-auth required
- Write operations (`set`, `reset`) are gated on `modify_campaigns = 1` AND `user_level > 6`
- All writes are logged to `vicidial_admin_log` with timestamp, user, IP, and the SQL executed
- The API only accepts GET requests with sanitised parameters — campaign IDs are stripped to `[a-zA-Z0-9_-]` before any DB query

---

## Compatibility

| Component | Version |
|---|---|
| ViciBox | 11.0.1 (tested) |
| VICIdial | 2.14-48 build 231115-1646 (tested) |
| PHP | 7.x / 8.x |
| MariaDB / MySQL | 10.x+ |
| Apache | 2.4+ (with mod_rewrite or direct access) |

Should work on any VICIdial 2.14.x install. For older versions where `auto_dial_level` column may be named differently, check with `DESCRIBE vicidial_campaigns` and update the column references in `cdl_api.php` if needed.

---

## File reference

### `cdl_api.php`
Standalone REST-like endpoint. All parameters passed as GET query string.

| Parameter | Values | Description |
|---|---|---|
| `cdl_action` | `campaigns`, `get`, `set` | Action to perform |
| `cdl_u` | VICIdial username | Identifies and authorises the caller |
| `cdl_campaign` | Campaign ID | Required for `get`, `set`, `reset` |
| `cdl_dial_level` | `1.0` – `20.0` | Required for `set` |

### `patch_realtime_final.sh`
Idempotent bash + Python patcher. Safe to re-run. Adds two blocks to `realtime_report.php`:
- A no-op marker block at line ~83 (removes old handler blocks from previous versions)
- The control row HTML + JavaScript block immediately before the `realtime_content` span

---

*Built for the Beltalk / VICIdial team. Maintained by the infrastructure group.*
