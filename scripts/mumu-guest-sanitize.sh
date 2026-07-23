#!/system/bin/sh
set -eu

MODE="${1:-init-only}"
EXPECTED_VENDOR_SHA256="${2:-}"
RECOVERY=/data/local/tmp/mumu-magisk-vendor-backup
TMP="$RECOVERY/init.rc.new"
PROBE_DIR=/data/local/tmp/mumu-magisk-namespace-probe

fail() {
    echo "SANITIZE_REFUSED: $*" >&2
    exit 1
}

find_magisk_busybox() {
    for CANDIDATE in /data/adb/magisk/busybox /sbin/.magisk/busybox/busybox; do
        if test -x "$CANDIDATE"; then
            echo "$CANDIDATE"
            return 0
        fi
    done
    fail "Kitsune BusyBox was not found"
}

find_unshare() {
    for CANDIDATE in /system/bin/unshare /system/xbin/unshare; do
        if test -x "$CANDIDATE"; then
            echo "$CANDIDATE"
            return 0
        fi
    done
    fail "unshare was not found"
}

ensure_recovery_dir() {
    mkdir -p "$RECOVERY"
    chmod 700 "$RECOVERY"
}

validate_vendor_hash() {
    if test -z "$EXPECTED_VENDOR_SHA256" && test -f "$RECOVERY/vendor.sha256"; then
        EXPECTED_VENDOR_SHA256="$(sed -n '1p' "$RECOVERY/vendor.sha256")"
    fi
    test "${#EXPECTED_VENDOR_SHA256}" -eq 64 ||
        fail "a captured 64-character vendor SHA-256 is required"
    echo "$EXPECTED_VENDOR_SHA256" | grep -qE '^[0-9A-Fa-f]{64}$' ||
        fail "vendor SHA-256 is not hexadecimal"
    EXPECTED_VENDOR_SHA256="$(echo "$EXPECTED_VENDOR_SHA256" | tr A-F a-f)"
}

capture_vendor_clients() {
    validate_vendor_hash
    ensure_recovery_dir

    FOUND=0
    for CANDIDATE in /system/bin/su /system/xbin/su; do
        if test -e "$CANDIDATE" || test -L "$CANDIDATE"; then
            set -- $(sha256sum "$CANDIDATE")
            CANDIDATE_SHA256="$(echo "$1" | tr A-F a-f)"
            test "$CANDIDATE_SHA256" = "$EXPECTED_VENDOR_SHA256" ||
                fail "$CANDIDATE does not match the captured MuMu vendor binary"
            NAME="$(echo "$CANDIDATE" | tr / _)"
            if ! test -f "$RECOVERY/$NAME.before"; then
                cp -p "$CANDIDATE" "$RECOVERY/$NAME.before"
            fi
            set -- $(sha256sum "$RECOVERY/$NAME.before")
            BACKUP_SHA256="$(echo "$1" | tr A-F a-f)"
            test "$BACKUP_SHA256" = "$EXPECTED_VENDOR_SHA256" ||
                fail "recovery copy for $CANDIDATE failed verification"
            FOUND=$((FOUND + 1))
            echo "CAPTURED_VENDOR_CLIENT path=$CANDIDATE sha256=$CANDIDATE_SHA256"
        fi
    done
    test "$FOUND" -gt 0 || fail "no visible MuMu vendor su client was found"

    printf '%s\n' "$EXPECTED_VENDOR_SHA256" > "$RECOVERY/vendor.sha256.new"
    chmod 600 "$RECOVERY/vendor.sha256.new"
    mv -f "$RECOVERY/vendor.sha256.new" "$RECOVERY/vendor.sha256"
    sync
    echo "VENDOR_CAPTURE_OK count=$FOUND sha256=$EXPECTED_VENDOR_SHA256 recovery=$RECOVERY"
}

print_vendor_clients() {
    FOUND=0
    for CANDIDATE in /system/bin/su /system/xbin/su; do
        if test -e "$CANDIDATE" || test -L "$CANDIDATE"; then
            sha256sum "$CANDIDATE"
            FOUND=$((FOUND + 1))
        fi
    done
    test "$FOUND" -gt 0 || fail "no visible MuMu vendor su client was found"
    echo "VENDOR_HASH_SCAN_OK count=$FOUND"
}

assert_system_install() {
    test -f /system/etc/init/magisk/config || fail "Kitsune system config is missing"
    grep -qx 'SYSTEMMODE=true' /system/etc/init/magisk/config ||
        fail "Kitsune is not configured for System Mode"
    test -f /system/etc/init/magisk.rc || fail "Kitsune init RC is missing"
    test -x /system/etc/init/magisk/magisk64 || fail "Kitsune magisk64 is missing"
    # -V queries the running daemon and is unavailable before the first
    # System Mode boot.  -c reports the version embedded in this exact binary.
    test "$(/system/etc/init/magisk/magisk64 -c)" = '31.0-kitsune:MAGISK:R (31000)' ||
        fail "Kitsune system binary is not the pinned 31.0-kitsune (31000) build"
    test -s "$RECOVERY/vendor.sha256" || fail "captured vendor hash is missing"
    echo "SYSTEM_INSTALL_GATE_OK"
}

assert_private_namespace() {
    BB="$1"
    test -n "${MUMU_SANITIZE_PARENT_NS:-}" ||
        fail "private mode must be entered by the sanitizer"
    CURRENT_NS="$(readlink /proc/self/ns/mnt)"
    test "$CURRENT_NS" != "$MUMU_SANITIZE_PARENT_NS" ||
        fail "unshare did not create a new mount namespace"

    "$BB" mount --make-rprivate / ||
        fail "could not make the child mount namespace recursively private"
    ROOT_MOUNT_INFO="$(awk '$5 == "/" { print; exit }' /proc/self/mountinfo)"
    test -n "$ROOT_MOUNT_INFO" || fail "root mount was not found"
    if echo "$ROOT_MOUNT_INFO" | grep -q ' shared:'; then
        fail "root mount is still shared in the child namespace"
    fi
}

run_namespace_probe_child() {
    BB="$(find_magisk_busybox)"
    assert_private_namespace "$BB"

    "$BB" mkdir -p "$PROBE_DIR"
    "$BB" mount -t tmpfs tmpfs "$PROBE_DIR" ||
        fail "temporary namespace mount failed"
    echo child-only > "$PROBE_DIR/marker"
    grep -q " $PROBE_DIR " /proc/self/mountinfo ||
        fail "temporary namespace mount was not visible in the child"
    "$BB" umount "$PROBE_DIR" || fail "temporary namespace unmount failed"
    test ! -e "$PROBE_DIR/marker" ||
        fail "temporary child mount remained visible after unmount"
    echo "NAMESPACE_CHILD_OK parent=$MUMU_SANITIZE_PARENT_NS child=$(readlink /proc/self/ns/mnt)"
}

run_namespace_probe() {
    BB="$(find_magisk_busybox)"
    UNSHARE="$(find_unshare)"
    PARENT_NS="$(readlink /proc/self/ns/mnt)"
    if grep -q " $PROBE_DIR " /proc/self/mountinfo; then
        fail "a stale namespace probe mount exists in the parent namespace"
    fi
    "$BB" rm -f "$PROBE_DIR/marker" 2>/dev/null || true
    if test -d "$PROBE_DIR"; then
        "$BB" rmdir "$PROBE_DIR" || fail "namespace probe directory is not empty"
    fi
    "$BB" mkdir -p "$PROBE_DIR"

    MUMU_SANITIZE_PARENT_NS="$PARENT_NS" \
        "$UNSHARE" -m "$BB" sh "$0" namespace-probe-child

    test ! -e "$PROBE_DIR/marker" ||
        fail "a child-only mount propagated to the parent namespace"
    if grep -q " $PROBE_DIR " /proc/self/mountinfo; then
        fail "the temporary mount propagated to the parent namespace"
    fi
    "$BB" rmdir "$PROBE_DIR"
    echo "NAMESPACE_PROBE_OK parent=$PARENT_NS"
}

disable_vendor_daemon() {
    MATCHES="$(grep -R -l -E '^service su_daemon /system/xbin/(mu_bak|su) --daemon$' \
        /system/etc/init /vendor/etc/init 2>/dev/null || true)"
    set -- $MATCHES
    test "$#" -eq 1 || fail "expected one known su_daemon RC file, found $#"
    RC="$1"

    SERVICE_LINE="$(grep -E '^service su_daemon /system/xbin/(mu_bak|su) --daemon$' "$RC" || true)"
    case "$SERVICE_LINE" in
        'service su_daemon /system/xbin/mu_bak --daemon')
            SERVICE_PATTERN='^service su_daemon /system/xbin/mu_bak --daemon$'
            SED_SERVICE_PATTERN='^service su_daemon \/system\/xbin\/mu_bak --daemon$'
            ;;
        'service su_daemon /system/xbin/su --daemon')
            SERVICE_PATTERN='^service su_daemon /system/xbin/su --daemon$'
            SED_SERVICE_PATTERN='^service su_daemon \/system\/xbin\/su --daemon$'
            ;;
        *) fail "su_daemon declaration is missing or ambiguous in $RC" ;;
    esac

    test "$(grep -c "$SERVICE_PATTERN" "$RC" || true)" -eq 1 ||
        fail "expected exactly one known su_daemon declaration"

    ensure_recovery_dir
    trap 'rm -f "$TMP"' EXIT

    if ! grep -qE '^[^ ]+ /system [^ ]+ rw,' /proc/mounts; then
        mount -o rw,remount /system 2>/dev/null ||
            mount -o remount,rw /system 2>/dev/null ||
            fail "/system did not remount read-write"
    fi
    test -w "$RC" || fail "$RC is not writable"

    test -f "$RECOVERY/init.rc.before" || cp -p "$RC" "$RECOVERY/init.rc.before"
    if sed -n "/$SED_SERVICE_PATTERN/,/^service /p" "$RC" |
        grep -qE '^[[:space:]]+disabled([[:space:]]|$)'; then
        echo "su_daemon is already disabled"
    else
        sed "/$SED_SERVICE_PATTERN/a\\
    disabled
" "$RC" > "$TMP"
        sed -n "/$SED_SERVICE_PATTERN/,/^service /p" "$TMP" |
            grep -qE '^[[:space:]]+disabled([[:space:]]|$)' ||
            fail "failed to construct the disabled service stanza"
        cat "$TMP" > "$RC"
        cmp -s "$TMP" "$RC" || fail "init RC verification failed after write"
    fi

    sync
    sed -n "/$SED_SERVICE_PATTERN/,/^service /p" "$RC"
    echo "INIT_SANITIZE_OK rc=$RC recovery=$RECOVERY"
}

remove_vendor_clients_private() {
    BB="$(find_magisk_busybox)"
    assert_private_namespace "$BB"

    "$BB" umount -l /system/bin ||
        fail "could not detach the Magisk /system/bin overlay in the private namespace"
    test "$(readlink /system/bin/su 2>/dev/null || true)" != './magisk' ||
        fail "Magisk /system/bin overlay is still visible in the private namespace"

    REMOVED=0
    for CANDIDATE in /system/bin/su /system/xbin/su; do
        if test -e "$CANDIDATE" || test -L "$CANDIDATE"; then
            set -- $("$BB" sha256sum "$CANDIDATE")
            CANDIDATE_SHA256="$(echo "$1" | tr A-F a-f)"
            test "$CANDIDATE_SHA256" = "$EXPECTED_VENDOR_SHA256" ||
                fail "$CANDIDATE does not match the captured MuMu vendor binary"
            NAME="$(echo "$CANDIDATE" | tr / _)"
            test -f "$RECOVERY/$NAME.before" ||
                "$BB" cp -p "$CANDIDATE" "$RECOVERY/$NAME.before"
            "$BB" rm -f "$CANDIDATE"
            REMOVED=$((REMOVED + 1))
            echo "REMOVED_VENDOR_CLIENT path=$CANDIDATE sha256=$CANDIDATE_SHA256"
        else
            echo "VENDOR_CLIENT_ABSENT path=$CANDIDATE"
        fi
    done

    for CANDIDATE in /system/bin/su /system/xbin/su; do
        if test -e "$CANDIDATE" || test -L "$CANDIDATE"; then
            fail "$CANDIDATE still exists after sanitation"
        fi
    done
    "$BB" sync
    echo "CLIENT_SANITIZE_OK removed=$REMOVED recovery=$RECOVERY"
}

case "$MODE" in
    vendor-hash)
        print_vendor_clients
        ;;
    system-gate)
        assert_system_install
        ;;
    prepare)
        test -n "$EXPECTED_VENDOR_SHA256" ||
            fail "prepare mode requires the currently visible vendor su SHA-256"
        capture_vendor_clients
        disable_vendor_daemon
        echo "SANITIZE_OK mode=prepare recovery=$RECOVERY"
        ;;
    init-only)
        disable_vendor_daemon
        echo "SANITIZE_OK mode=init-only recovery=$RECOVERY"
        ;;
    namespace-probe)
        run_namespace_probe
        echo "SANITIZE_OK mode=namespace-probe"
        ;;
    namespace-probe-child)
        run_namespace_probe_child
        ;;
    all)
        validate_vendor_hash
        disable_vendor_daemon
        run_namespace_probe
        BB="$(find_magisk_busybox)"
        UNSHARE="$(find_unshare)"
        PARENT_NS="$(readlink /proc/self/ns/mnt)"
        MUMU_SANITIZE_PARENT_NS="$PARENT_NS" \
            "$UNSHARE" -m "$BB" sh "$0" all-private "$EXPECTED_VENDOR_SHA256"
        echo "SANITIZE_OK mode=all recovery=$RECOVERY"
        ;;
    all-private)
        validate_vendor_hash
        remove_vendor_clients_private
        ;;
    *) fail "mode must be vendor-hash, system-gate, prepare, init-only, namespace-probe, or all" ;;
esac
