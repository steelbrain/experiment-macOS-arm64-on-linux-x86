#!/bin/sh

set -eu

expected_cpus=$1
network_url=$2
network_token=$3
work=/private/tmp/27on86-workload.$$
mkdir -p "$work"

cleanup()
{
    find "$work" -type f -delete 2>/dev/null || true
    rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

architecture=$(/usr/bin/uname -m)
online_cpus=$(/usr/sbin/sysctl -n hw.ncpu)
active_cpus=$(/usr/sbin/sysctl -n hw.activecpu)
logical_cpus=$(/usr/sbin/sysctl -n hw.logicalcpu)
test "$architecture" = arm64
test "$online_cpus" = "$expected_cpus"
test "$active_cpus" = "$expected_cpus"
test "$logical_cpus" = "$expected_cpus"
echo "architecture=$architecture"
echo "online_cpus=$online_cpus"

/usr/bin/perl - <<'PL'
use strict;
use warnings;

my $size = 256 * 1024 * 1024;
my $page = 4096;
my $memory = "\0" x $size;
my $checksum = 0;
for (my $offset = 0; $offset < $size; $offset += $page) {
    my $value = ($offset / $page) & 0xff;
    substr($memory, $offset, 1) = chr($value);
    $checksum += ord(substr($memory, $offset, 1));
}
my $expected = ($size / $page / 256) * 32640;
die "memory checksum mismatch: $checksum != $expected\n"
    if $checksum != $expected;
print "memory_bytes=$size\n";
print "memory_checksum=$checksum\n";
PL

pids=
worker=0
while test "$worker" -lt "$expected_cpus"; do
    (
        /bin/dd if=/dev/zero bs=1048576 count=1 2>/dev/null |
            /usr/bin/openssl dgst -sha256 >"$work/cpu.$worker"
    ) &
    pids="$pids $!"
    worker=$((worker + 1))
done
for pid in $pids; do
    wait "$pid"
done
worker_count=$(find "$work" -name 'cpu.*' -type f | /usr/bin/wc -l | tr -d ' ')
unique_hashes=$(awk '{print $NF}' "$work"/cpu.* | sort -u | /usr/bin/wc -l | tr -d ' ')
test "$worker_count" = "$expected_cpus"
test "$unique_hashes" = 1
echo "parallel_workers=$worker_count"
echo "parallel_hash=$(awk 'NR == 1 {print $NF}' "$work"/cpu.0)"

intercpu_counter=$(/usr/bin/perl -Mthreads -Mthreads::shared -e '
    my $workers = shift;
    my $rounds = 64;
    my $turn :shared = 0;
    my $counter :shared = 0;
    my @threads;
    for my $worker (0 .. $workers - 1) {
        push @threads, threads->create(sub {
            for (1 .. $rounds) {
                lock($turn);
                cond_wait($turn) while $turn != $worker;
                ++$counter;
                $turn = ($turn + 1) % $workers;
                cond_broadcast($turn);
            }
        });
    }
    $_->join for @threads;
    die "inter-CPU counter mismatch: $counter\n"
        if $counter != $workers * $rounds;
    print $counter;
' "$expected_cpus")
test "$intercpu_counter" = "$((expected_cpus * 64))"
echo "intercpu_counter=$intercpu_counter"

/bin/dd if=/dev/zero of="$work/storage.bin" bs=1048576 count=32 2>/dev/null
/bin/sync
storage_hash=$(/usr/bin/cksum "$work/storage.bin" | awk '{print $1 ":" $2}')
readback_hash=$(/bin/cat "$work/storage.bin" | /usr/bin/cksum | awk '{print $1 ":" $2}')
test "$storage_hash" = "$readback_hash"
echo "storage_bytes=33554432"
echo "storage_hash=$storage_hash"

received=$(/usr/bin/curl -fsS "$network_url")
test "$received" = "$network_token"
echo "network_payload=$received"

/usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC,sleep -e '
    my $start = clock_gettime(CLOCK_MONOTONIC);
    sleep(2);
    my $elapsed = int((clock_gettime(CLOCK_MONOTONIC) - $start) * 1_000_000_000);
    die "timer interval outside tolerance: $elapsed\n"
        if $elapsed < 1_900_000_000 || $elapsed > 10_000_000_000;
    print "timer_elapsed_ns=$elapsed\n";
'

echo "workload_status=pass"
