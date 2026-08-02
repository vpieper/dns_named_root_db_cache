#!/bin/bash

# ==========================================
# Configuration Variables
# ==========================================
# Where to send the success or failure alerts
ADMIN_EMAIL="your.email@example.com" 

# The URL and the standard Debian destination path for root hints
HINTS_URL="https://internic.net/domain/named.root"
HINTS_DEST="/usr/share/dns/root.hints" 

# The URL and the destination path for the secondary hints file (db.root)
# (Reverted to db.cache so BIND receives the correct hints format)
ZONE_URL="https://internic.net/domain/db.cache"
ZONE_DEST="/etc/bind/db.root" 

# ==========================================
# Helper Function
# ==========================================
send_alert() {
    local subject=$1
    local message=$2
    echo -e "$message" | mail -s "$subject" "$ADMIN_EMAIL"
}

# ==========================================
# Execution
# ==========================================

# 1. Create temporary files
TEMP_HINTS=$(mktemp)
TEMP_ZONE=$(mktemp)

# 2. Download standard Root Hints
if ! curl -f -s -S -o "$TEMP_HINTS" "$HINTS_URL" 2> /tmp/hints_err.log; then
    ERROR_MSG=$(cat /tmp/hints_err.log)
    send_alert "CRITICAL: BIND Root Hints Update Failed" "Failed to download $HINTS_URL.\n\nError: $ERROR_MSG\n\nYour live files were untouched and BIND was NOT reloaded."
    rm -f "$TEMP_HINTS" "$TEMP_ZONE" /tmp/hints_err.log
    exit 1
fi

# 3. Download db.cache for db.root
if ! curl -f -s -S -o "$TEMP_ZONE" "$ZONE_URL" 2> /tmp/zone_err.log; then
    ERROR_MSG=$(cat /tmp/zone_err.log)
    send_alert "CRITICAL: BIND Root Zone Update Failed" "Failed to download $ZONE_URL.\n\nError: $ERROR_MSG\n\nYour live files were untouched and BIND was NOT reloaded."
    rm -f "$TEMP_HINTS" "$TEMP_ZONE" /tmp/hints_err.log /tmp/zone_err.log
    exit 1
fi

# 4. Apply the updates
# mktemp creates files with strict 600 permissions. We must grant read access 
# to the 'bind' user before moving them, otherwise 'rndc reload' will fail.
chmod 644 "$TEMP_HINTS" "$TEMP_ZONE"

mv "$TEMP_HINTS" "$HINTS_DEST"
mv "$TEMP_ZONE" "$ZONE_DEST"

# 5. Reload BIND
if /usr/sbin/rndc reload > /tmp/rndc_out.log 2>&1; then
    send_alert "SUCCESS: BIND Root Files Updated" "The scheduled update completed successfully.\n\nFiles updated:\n- $HINTS_DEST\n- $ZONE_DEST\n\nBIND cache was gracefully reloaded."
else
    ERROR_MSG=$(cat /tmp/rndc_out.log)
    send_alert "WARNING: BIND Files Downloaded but Reload Failed" "The root files downloaded successfully, but 'rndc reload' threw an error.\n\nError: $ERROR_MSG"
    rm -f /tmp/hints_err.log /tmp/zone_err.log /tmp/rndc_out.log
    exit 1
fi

# 6. Cleanup
rm -f /tmp/hints_err.log /tmp/zone_err.log /tmp/rndc_out.log
exit 0
