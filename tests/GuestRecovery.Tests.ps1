$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$gitPath = (Get-Command git.exe -ErrorAction Stop).Source
$bashPath = Join-Path (Split-Path -Parent (Split-Path -Parent $gitPath)) 'bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath -PathType Leaf)) { throw 'Git for Windows Bash is required for guest recovery tests.' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mumu-guest-recovery-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $source = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\mumu-guest-sanitize.sh'))
    $dispatch = $source.IndexOf('case "$MODE" in', [StringComparison]::Ordinal)
    if ($dispatch -lt 0) { throw 'Guest sanitizer dispatch was not found.' }
    # Exercise the real recovery function against ordinary temporary files.
    # Replace Android discovery/service operations; no host or guest system files are used.
    $fixture = @'
FIXTURE="$1"
select_vendor_daemon() {
    RC="$CASE_DIR/current.rc"
    SERVICE_PATTERN='^service su_daemon /system/xbin/mu_bak --daemon$'
    SED_SERVICE_PATTERN='^service su_daemon \/system\/xbin\/mu_bak --daemon$'
}
ensure_init_writable() { test -w "$RC"; }
getprop() { if test -f "$CASE_DIR/started"; then echo running; else echo stopped; fi; }
start() { test "$1" = su_daemon || exit 91; touch "$CASE_DIR/started"; }
sync() { :; }
new_case() {
    CASE_DIR="$FIXTURE/$1"
    RECOVERY="$CASE_DIR/recovery"
    TMP="$RECOVERY/init.rc.new"
    mkdir -p "$RECOVERY"
    touch "$CASE_DIR/started"
    cat > "$CASE_DIR/original.rc" <<'RCEND'
# An unrelated original comment must survive.
service su_daemon /system/xbin/mu_bak --daemon
    class late_start
    seclabel u:r:su:s0

service other /system/bin/other
    class main
RCEND
    cp "$CASE_DIR/original.rc" "$CASE_DIR/current.rc"
    select_vendor_daemon
}
make_disabled() {
    sed "/$SED_SERVICE_PATTERN/a\\
    disabled
" "$CASE_DIR/original.rc" > "$RC"
}
expect_refusal() {
    cp "$RC" "$CASE_DIR/untouched.rc"
    if (enable_vendor_daemon_for_prepare) > "$CASE_DIR/refusal.log" 2>&1; then
        echo "Recovery incorrectly accepted $CASE_DIR" >&2
        exit 92
    fi
    grep -q SANITIZE_REFUSED "$CASE_DIR/refusal.log"
    cmp -s "$RC" "$CASE_DIR/untouched.rc"
}

new_case healthy
(enable_vendor_daemon_for_prepare)
cmp -s "$RC" "$CASE_DIR/original.rc"
test ! -f "$RECOVERY/init.rc.before"

new_case recover
cp "$CASE_DIR/original.rc" "$RECOVERY/init.rc.before"
make_disabled
(enable_vendor_daemon_for_prepare)
cmp -s "$RC" "$CASE_DIR/original.rc"
test ! -f "$TMP"

new_case missing_backup
make_disabled
expect_refusal

new_case changed_rc
cp "$CASE_DIR/original.rc" "$RECOVERY/init.rc.before"
make_disabled
printf '\n# An external edit\n' >> "$RC"
expect_refusal

new_case originally_disabled
make_disabled
cp "$RC" "$RECOVERY/init.rc.before"
expect_refusal

new_case stopped
rm -f "$CASE_DIR/started"
(enable_vendor_daemon_for_prepare)
test -f "$CASE_DIR/started"
cmp -s "$RC" "$CASE_DIR/original.rc"
echo 'Guest recovery tests passed (6 scenarios).'
'@
    $testScript = Join-Path $testRoot 'recovery.sh'
    [IO.File]::WriteAllText($testScript, ($source.Substring(0, $dispatch) + $fixture).Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
    & $bashPath --noprofile --norc ($testScript.Replace('\', '/')) ($testRoot.Replace('\', '/'))
    if ($LASTEXITCODE -ne 0) { throw "Guest recovery tests failed with exit code $LASTEXITCODE." }
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^mumu-guest-recovery-[a-f0-9]{32}$') { throw 'Unsafe guest fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
