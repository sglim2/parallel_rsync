# parallel-rsync

A bash script for running multiple `rsync` transfers in parallel across a set of directories.

## Why parallel rsync?

`rsync` is single-threaded per invocation, and rarely saturates networking with the one stream. Running multiple `rsync` jobs concurrently can improve throughput.

## When is this useful?

Most effective when:

- Data is split into many directories 
- Each directory can be transferred independently
- The backend storage supports concurrent reads/writes
- You are copying across high-bandwidth links (e.g. datacentre, HPC)

## When *not* to use it

Parallelisation may **impact performance** if:

- Source or destination is IOPS-limited (e.g. single HDD)
- Network is already saturated by a single stream
- Too many jobs cause contention (CPU, disk, or metadata locking)
- When it starts to p\*ss off other users on multi-tenancy systems

## Features

- Parallel execution using `xargs`
- Configurable job count
- Per-directory logging
- Resume-friendly (`--partial`)
- Preserve numeric IDs (`--numeric-ids`)
- Exclude directories via repeated `-X` flags

## Usage

```bash
./parallel_rsync.sh \
  -s <SRC_HOST> \
  -S <SRC_BASE> \
  -D <DST_BASE> \
  [-j JOBS] \
  [-X DIRNAME ...]
```

## Example

```bash
./parallel_rsync.sh \
  -s 192.168.10.21 \
  -S /mnt/archive \
  -D /mnt/data/archive_bak1 \
  -j 8 \
  -X skipdir1 \
  -X skipdir2
```
## Logs

Logs are written per directory to:
```bash
/tmp/parallel_rsync-<timestamp>/
```
Each directory has its own log file, making it easy to retry or debug individual transfers.

## Notes

 - Uses SSH for transport (key-based auth recommended)
 - Designed for directory-level parallelism (not file-level), and files under the top-level directory will be skipped.
 - Safe to re-run (rsync is incremental)
 - It does not recurse when building the parallel work list, only the top-level folders are used as parallel work items.
 - excludes via '-X' refer to top-level subdirs only.





