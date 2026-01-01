# Frequently Asked Questions

## Scores

### Why is my score different each run?

Normal variance of 2-5% is expected due to:
- Background processes
- Thermal state
- System load
- Disk caching effects

For most accurate results:
1. Close other applications
2. Wait for system to cool down
3. Run in normal mode (not quick)
4. Run multiple times and compare

### Why is my M1 score not exactly 1000?

The baseline values are calibrated from typical M1 performance, but:
- Individual chips vary slightly
- SSD models differ
- macOS version affects some tests
- Thermal conditions impact results

A score of 950-1050 for an M1 is normal.

### Why is Disk score so variable?

Disk benchmarks depend on:
- SSD model and generation
- Available free space
- Filesystem state
- Other I/O activity

We bypass the cache with `F_NOCACHE`, but some variance remains.

### How do scores compare to Geekbench?

They don't directly compare because:
- Different test workloads
- Different scoring algorithms
- Different baselines

Use Apple Silicon Bench for comparing Apple Silicon systems. Use Geekbench for cross-platform comparisons.

## Benchmarks

### What is the difference between quick and normal mode?

| Aspect | Quick Mode | Normal Mode |
|--------|------------|-------------|
| Duration | ~3s/test | 10s/test |
| Accuracy | Good | Better |
| Variance | Higher | Lower |
| Use case | Development | Final results |

### Can I run only specific benchmarks?

Yes, use the `--only` flag:
```bash
osx-bench run --only cpu-single
osx-bench run --only gpu,memory
osx-bench run --only cpu-single,cpu-multi,memory,disk
```

### Why does GPU benchmark fail on my Mac?

The GPU benchmark requires:
- Apple Silicon (M1 or later)
- Metal support
- macOS 13.0 or later

Intel Macs will show "Failed" for GPU tests.

### How do I test thermal throttling?

Use stress mode:
```bash
osx-bench run --stress
```

This runs 60-second tests, enough to trigger throttling on most systems. Compare "burst" (normal mode) vs "sustained" (stress mode) scores.

## Technical

### Why use geometric mean instead of arithmetic mean?

Geometric mean:
- Handles different units properly (GFLOPS vs MB/s vs ns)
- Prevents single outlier from dominating
- Is standard in benchmarking (SPEC, etc.)

See [Scoring Methodology](Scoring-Methodology.md) for details.

### How does cache bypass work in disk tests?

We use `fcntl(fd, F_NOCACHE, 1)` which tells macOS:
- Don't cache reads from this file
- Don't buffer writes
- Bypass the unified buffer cache

This measures actual SSD speed, not RAM speed.

### Why are Metal shaders compiled at runtime?

Swift Package Manager doesn't compile `.metal` files like Xcode. Options:

1. **Runtime compilation** (our approach): Shader source as string, compile with `makeLibrary(source:)`
2. **Pre-compiled metallib**: Requires manual build step

We chose runtime compilation for simplicity and SPM compatibility. The ~100ms compilation overhead is negligible.

### How is multi-core score normalized?

We adjust for core count:
```
multiReference = singleCoreBaseline × 8 × (actualCores / 8)
```

This means:
- 8-core M1 → expected ~8× single-core
- 10-core M1 Pro → expected ~10× single-core (scaled)
- 4-core system → not penalized unfairly

### What frameworks are used?

All native macOS frameworks:
- **Accelerate**: SIMD/vDSP operations
- **CryptoKit**: AES-GCM encryption
- **Compression**: LZFSE algorithm
- **Metal**: GPU compute shaders
- **Foundation**: File I/O, system info

No external dependencies except `swift-argument-parser` for CLI.

## Troubleshooting

### "Command not found: osx-bench"

Make sure to:
1. Download/build the binary
2. Make it executable: `chmod +x osx-bench`
3. Remove quarantine: `xattr -cr osx-bench`
4. Either add to PATH or run with `./osx-bench`

### macOS asks for permission

The benchmark needs:
- Disk access (for disk benchmarks)
- GPU access (for Metal benchmarks)

Grant permissions when prompted, or run with reduced tests:
```bash
osx-bench run --only cpu-single,cpu-multi,memory
```

### Binary won't run (malware warning)

Apple's Gatekeeper may block unsigned binaries. Fix:
```bash
xattr -cr osx-bench
```

Or build from source:
```bash
git clone https://github.com/carlosacchi/apple-silicon-bench
cd apple-silicon-bench
swift build -c release
./.build/release/osx-bench run
```

### HTML report not generating

Check:
1. `~/Desktop/OSX-Bench-Reports/` directory exists
2. You have write permission to Desktop
3. Benchmark actually completed (not cancelled)

Reports are only generated after successful benchmark completion.
