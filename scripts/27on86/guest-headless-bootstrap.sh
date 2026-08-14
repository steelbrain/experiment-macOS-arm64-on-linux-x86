#!/bin/sh

set -eu

stage=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
boot_util=/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_boot_util

echo "starting APFS data-volume setup"
"$boot_util" 2 >"$stage/apfs-boot.log" 2>&1 &
boot_pid=$!
trap 'kill -INT "$boot_pid" 2>/dev/null || true' EXIT HUP INT TERM

stitched=0
count=0
while test "$count" -lt 180; do
    if test -d /System/Volumes/Data/private/var && test -d /private/var; then
        data_dev=$(/usr/bin/stat -f %d /System/Volumes/Data/private)
        private_dev=$(/usr/bin/stat -f %d /private)
        if test "$data_dev" = "$private_dev"; then
            stitched=1
            break
        fi
    fi
    count=$((count + 1))
    sleep 1
done

if test "$stitched" != 1; then
    echo "APFS firmlink setup did not complete" >&2
    tail -n 40 "$stage/apfs-boot.log" >&2
    exit 1
fi

# Firmlink visibility precedes the remaining volume-group notifications. Keep
# phase 2 alive long enough for those notifications to settle before configd
# opens the network stack.
echo "APFS firmlinks visible; settling volume-group setup"
sleep 60
kill -INT "$boot_pid" 2>/dev/null || true
wait "$boot_pid" 2>/dev/null || true
trap - EXIT HUP INT TERM
echo "APFS firmlinks ready after ${count}s"

mkdir -p /private/var/db/27on86 /private/var/root/.ssh /etc/ssh
cp "$stage/authorized_keys" /private/var/root/.ssh/authorized_keys
cp "$stage/ssh_host_ed25519_key" /etc/ssh/ssh_host_ed25519_key
cp "$stage/ssh_host_ed25519_key.pub" /etc/ssh/ssh_host_ed25519_key.pub
cp "$stage/headless-sshd.conf" /private/var/db/27on86/sshd_config
chmod 700 /private/var/root/.ssh /private/var/db/27on86
chmod 600 /private/var/root/.ssh/authorized_keys \
    /etc/ssh/ssh_host_ed25519_key /private/var/db/27on86/sshd_config
chmod 644 /etc/ssh/ssh_host_ed25519_key.pub

start_service()
{
    label=$1
    plist=$2
    if ! /bin/launchctl print "system/$label" >/dev/null 2>&1; then
        /bin/launchctl bootstrap system "$plist" >"$stage/$label.log" 2>&1
    fi
}

start_service com.apple.configd \
    /System/Library/LaunchDaemons/com.apple.configd.plist

count=0
address=
while test "$count" -lt 120; do
    address=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)
    if test -n "$address"; then
        break
    fi
    count=$((count + 1))
    sleep 1
done
if test -z "$address"; then
    echo "network did not acquire an IPv4 address" >&2
    exit 1
fi
echo "network ready: $address"

start_service com.apple.opendirectoryd \
    /System/Library/LaunchDaemons/com.apple.opendirectoryd.plist

count=0
while test "$count" -lt 60; do
    if /usr/bin/dscl . -read /Users/sshd >/dev/null 2>&1; then
        break
    fi
    count=$((count + 1))
    sleep 1
done
if test "$count" -ge 60; then
    echo "directory service did not expose the sshd account" >&2
    exit 1
fi

/usr/sbin/sshd -t -f /private/var/db/27on86/sshd_config
/bin/launchctl bootout system/org.qemu.27on86.sshd >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$stage/headless-sshd.plist" \
    >"$stage/org.qemu.27on86.sshd.log" 2>&1

count=0
while test "$count" -lt 30; do
    if /bin/launchctl print system/org.qemu.27on86.sshd 2>/dev/null |
        grep -q 'state = running'; then
        echo "headless SSH ready"
        exit 0
    fi
    count=$((count + 1))
    sleep 1
done

echo "sshd did not remain running" >&2
tail -n 40 /private/var/db/27on86/sshd.log >&2 || true
exit 1
