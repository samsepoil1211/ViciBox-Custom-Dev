#!/bin/bash
###############################################################################
# patch_list_column.sh — VICIdial Real-Time LIST ID/NAME column installer
#
# Universal installer for the LIST ID + LIST NAME custom columns patch.
#
# Just place this script and AST_timeonVDADall_patched.php in the same folder
# and run:    ./patch_list_column.sh
#
# Features:
#   - Auto-detects the live AST_timeonVDADall.php location on common installs
#   - Auto-detects the patched file (any of these names work):
#       AST_timeonVDADall_patched.php
#       AST_timeonVDADall.patched.php
#       AST_timeonVDADall.php (when shipped separately from the live one)
#   - Verifies the patched file contains the CUSTOM marker
#   - Times-tamped backup of the live file before any change
#   - PHP syntax check before deploying
#   - Preserves the live file's owner and permissions
#   - Safe to re-run — detects existing patch and skips
#   - Pass a custom live-file path as the first argument if auto-detect fails
###############################################################################
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 1. Locate the patched source file ─────────────────────────────────────────
PATCH_SRC=""
for f in "$SCRIPT_DIR/AST_timeonVDADall_patched.php" \
         "$SCRIPT_DIR/AST_timeonVDADall.patched.php" \
         "$SCRIPT_DIR"/AST_timeonVDADall*patched*.php \
         "$SCRIPT_DIR/AST_timeonVDADall.php"; do
    if [ -f "$f" ] && grep -q 'CUSTOM: List ID / List Name' "$f" 2>/dev/null; then
        PATCH_SRC="$f"; break
    fi
done

if [ -z "$PATCH_SRC" ]; then
    echo "ERROR: Patched AST_timeonVDADall*.php file not found in $SCRIPT_DIR"
    echo ""
    echo "       Place the patched file (containing the CUSTOM marker)"
    echo "       in the SAME folder as this script and re-run."
    echo ""
    echo "       Files present in $SCRIPT_DIR:"
    ls -1 "$SCRIPT_DIR"/*.php 2>/dev/null | sed 's/^/         /' || echo "         (no PHP files)"
    exit 1
fi

# ── 2. Locate the live target file ────────────────────────────────────────────
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    for p in /srv/www/htdocs/vicidial/AST_timeonVDADall.php \
             /var/www/html/vicidial/AST_timeonVDADall.php \
             /var/www/html/agc/AST_timeonVDADall.php \
             /var/www/agc/AST_timeonVDADall.php \
             /usr/share/astguiclient/AST_timeonVDADall.php; do
        [ -f "$p" ] && TARGET="$p" && break
    done
fi
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
    echo "ERROR: Could not auto-detect the live AST_timeonVDADall.php."
    echo "       Pass the full path explicitly:"
    echo "         $0 /path/to/your/vicidial/AST_timeonVDADall.php"
    exit 1
fi

# Safety: don't let user accidentally patch the patch source over itself
if [ "$(readlink -f "$TARGET")" = "$(readlink -f "$PATCH_SRC")" ]; then
    echo "ERROR: Live file and patch source resolve to the same file. Aborting."
    exit 1
fi

echo ">> Patched source: $PATCH_SRC"
echo ">> Live target:    $TARGET"

# ── 3. Skip if already patched ────────────────────────────────────────────────
if grep -q 'CUSTOM: List ID / List Name' "$TARGET"; then
    echo ">> Already patched. Nothing to do."
    exit 0
fi

# ── 4. Backup ────────────────────────────────────────────────────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${TARGET}.bak.${STAMP}"
cp -p "$TARGET" "$BACKUP" || { echo "ERROR: backup failed"; exit 3; }
echo ">> Backup:         $BACKUP"

# ── 5. PHP syntax check on the patched file ──────────────────────────────────
if command -v php >/dev/null 2>&1; then
    if ! php -l "$PATCH_SRC" >/dev/null 2>&1; then
        echo "ERROR: Patched file failed PHP syntax check:"
        php -l "$PATCH_SRC"
        echo ">> Live file unchanged. Patched source rejected."
        exit 5
    fi
    echo ">> PHP syntax:     OK"
else
    echo ">> PHP CLI not found; skipping syntax check"
fi

# ── 6. Capture current owner & perms, then deploy ────────────────────────────
OWNER=$(stat -c '%U:%G' "$TARGET" 2>/dev/null || echo "")
MODE=$(stat -c '%a' "$TARGET" 2>/dev/null || echo "")

cat "$PATCH_SRC" > "$TARGET" || { echo "ERROR: write to $TARGET failed"; exit 6; }

[ -n "$OWNER" ] && chown "$OWNER" "$TARGET" 2>/dev/null || true
[ -n "$MODE" ]  && chmod "$MODE"  "$TARGET" 2>/dev/null || true

echo ""
echo ">> DONE. LIST ID + LIST NAME columns deployed."
echo ">> To rollback:    cp -p '$BACKUP' '$TARGET'"
echo ">> Refresh:        hard-refresh the Real-Time report in your browser (Ctrl+F5)"
