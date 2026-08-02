#!/bin/bash

# ==========================================
# Configuration Variables
# ==========================================
# Where to send the success or failure alerts
ADMIN_EMAIL="your.email@example.com" 

# The URL and the standard Debian destination path for root hints
# (Removed 'www.' to bypass InterNIC's SSL certificate SAN mismatch)
HINTS_URL="https://internic.net/domain/named.root"
HINTS_DEST="/usr/share/dns/root.hints" 

# The URL and the destination path for the Hyperlocal root zone file
ZONE_URL="https://internic.net/domain/db.cache"
ZONE_DEST="/etc/bind/db.root" 

# ==========================================
# Helper Function
# ==========================================
# This function takes two arguments (Subject and Message) and emails them to you.
# The '-e' flag in echo allows it to read formatting like \n (new lines).
send_alert() {
    local subject=$1
    local message=$2
    echo -e "$message" | mail -s "$subject" "$ADMIN_EMAIL"
}

# ==========================================
# Execution
# ==========================================

# 1. Create temporary files
# We download to these hidden temporary files first. This guarantees we don't 
# overwrite your live BIND configuration with a broken file if the network drops.
TEMP_HINTS=$(mktemp)
TEMP_ZONE=$(mktemp)

# 2. Download Root Hints
# curl flags used here:
# -f : Fail fast (returns an error code if the server gives a 404/500)
# -s : Silent (hides the progress bar so it doesn't clutter your cron logs)
# -S : Show error (ensures the actual error message is still output if it fails)
if ! curl -f -s -S -o "$TEMP_HINTS" "$HINTS_URL" 2> /tmp/hints_err.log; then
    ERROR_MSG=$(cat /tmp/hints_err.log)
    send_alert "CRITICAL: BIND Root Hints Update Failed" "Failed to download $HINTS_URL.\n\nError: $ERROR_MSG\n\nYour live files were untouched and BIND was NOT reloaded."
    rm -f "$TEMP_HINTS" "$TEMP_ZONE" /tmp/hints_err.log
    exit 1 # Stop the script immediately
fi

# 3. Download Root Zone
# Uses the exact same curl logic as above.
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
# We use 'rndc reload' to read the new files into memory without dropping 
# the active DNS cache or stopping the daemon.
if /usr/sbin/rndc reload > /tmp/rndc_out.log 2>&1; then
    # Everything worked perfectly. Send the confirmation email.
    send_alert "SUCCESS: BIND Root Files Updated" "The scheduled update completed successfully.\n\nFiles updated:\n- $HINTS_DEST\n- $ZONE_DEST\n\nBIND cache was gracefully reloaded."
else
    # The files downloaded, but BIND refused to reload.
    ERROR_MSG=$(cat /tmp/rndc_out.log)
    send_alert "WARNING: BIND Files Downloaded but Reload Failed" "The root files downloaded successfully, but 'rndc reload' threw an error.\n\nError: $ERROR_MSG"
    rm -f /tmp/hints_err.log /tmp/zone_err.log /tmp/rndc_out.log
    exit 1
fi

# 6. Cleanup
# Delete the temporary log files before the script finishes.
rm -f /tmp/hints_err.log /tmp/zone_err.log /tmp/rndc_out.log
exit 0
