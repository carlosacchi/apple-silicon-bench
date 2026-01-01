# Apple Silicon Bench Wiki

Welcome to the Apple Silicon Bench documentation.

## Quick Links

- [Scoring Methodology](Scoring-Methodology.md) - How scores are calculated
- [Benchmark Details](Benchmark-Details.md) - Technical details of each test
- [FAQ](FAQ.md) - Frequently asked questions

## What is Apple Silicon Bench?

A native macOS benchmark tool designed specifically for Apple Silicon processors (M1, M2, M3, M4, M5). It provides:

- **Transparent scoring** - Know exactly what's being measured
- **No cloud/account required** - Everything runs locally
- **Thermal awareness** - Detect throttling impact
- **Lightweight** - ~2MB binary, no dependencies

## Basic Usage

```bash
# Run all benchmarks (default: 10s per test)
osx-bench run

# Quick mode (faster, less accurate)
osx-bench run --quick

# Specific benchmarks only
osx-bench run --only cpu-single,gpu

# System information
osx-bench info
```

## Benchmark Categories

| Category | Tests | Weight |
|----------|-------|--------|
| CPU Single-Core | Integer, Float, SIMD, Crypto, Compression | 25% |
| CPU Multi-Core | Same as single, parallelized | 25% |
| Memory | Read, Write, Copy, Latency | 15% |
| Disk | Seq Read/Write, Random Read/Write | 15% |
| GPU (Metal) | Compute, Particles, Blur, Edge | 20% |

## Score Interpretation

- **1000** = M1 base chip baseline
- **>1000** = Faster than M1 base
- **<1000** = Slower than M1 base

Example scores:
- M1 base: ~1000
- M1 Pro: ~1100-1200
- M2: ~1150
- M3: ~1250
- M4: ~1400+

*(Actual scores depend on specific tests and thermal conditions)*

## HTML Reports

After each benchmark, a detailed report is saved to:
```
~/Desktop/OSX-Bench-Reports/osx-bench-report-YYYY-MM-DD_HH-mm-ss.html
```

Reports include:
- System information
- Score breakdown with charts
- Thermal progression
- Detailed results per test

## Getting Help

- [GitHub Issues](https://github.com/carlosacchi/apple-silicon-bench/issues)
- [README](https://github.com/carlosacchi/apple-silicon-bench#readme)
