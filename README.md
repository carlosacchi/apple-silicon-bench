# Apple Silicon Bench

**A native macOS benchmark tool for Apple Silicon Macs (M-series and A-series)**

[![Release](https://img.shields.io/github/v/release/carlosacchi/apple-silicon-bench)](https://github.com/carlosacchi/apple-silicon-bench/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)

A lightweight, native Swift benchmark tool designed specifically for Apple Silicon processors (M1, M2, M3 Family, M4 Family, M5 Family (like Pro, Max), A18 Pro). Supports all M-series and A-series chips with comprehensive CPU, GPU, memory, disk, and AI benchmarks.

## Features

- **CPU Single-Core & Multi-Core**: Integer, floating-point, SIMD, cryptography, compression
- **GPU Benchmark (Metal)**: Compute shaders, particle simulation, image processing
- **Memory Benchmark**: Bandwidth and latency measurements
- **Disk Benchmark**: Sequential and random I/O with cache bypass
- **AI/ML Benchmark (NEW in v2.0)**: CoreML inference (CPU/GPU/Neural Engine), BNNS operations
- **Thermal Monitoring**: Real-time throttling detection
- **HTML Reports**: Beautiful interactive reports saved to Desktop
- **Lightweight**: ~2MB standalone binary, no dependencies

## Quick Start

### Download Binary

```bash
curl -LO https://github.com/carlosacchi/apple-silicon-bench/releases/latest/download/osx-bench-macos-arm64.tar.gz
tar -xzf osx-bench-macos-arm64.tar.gz
xattr -cr osx-bench && chmod +x osx-bench
./osx-bench run
```

### Build from Source

```bash
git clone https://github.com/carlosacchi/apple-silicon-bench.git
cd apple-silicon-bench
swift build -c release
./.build/release/osx-bench run
```

## Usage

```bash
# Full benchmark (recommended)
osx-bench run

# Quick mode (~3s per test, less accurate)
osx-bench run --quick

# Custom duration
osx-bench run --duration 30

# Stress test (60s per test)
osx-bench run --stress

# Selective benchmarks
osx-bench run --only cpu-single,gpu
osx-bench run --only memory,disk
osx-bench run --only ai

# AI benchmark options
osx-bench run --only ai --model-path /path/to/model.mlmodelc
osx-bench run --offline  # Skip AI if model not cached

# Advanced profiling (v2.1.0+)
osx-bench run --advanced  # Stride sweep, QD matrix, thread scaling

# Multiple passes with median (v2.2.0+)
osx-bench run --repeats 3  # Run 3 passes, report median scores

# System info
osx-bench info
osx-bench info --extended

# Export results
osx-bench run --export results.json
```

## Scoring

### Total Score
- **Baseline**: M1 base chip = 1000 points per category (calibrated from median of 5 full runs)
- **Method**: Geometric mean of ratios (commonly used in benchmark suites)
- **Weights**: CPU-Single 25%, CPU-Multi 25%, Memory 15%, Disk 15%, GPU 20%

| Chip | Expected Score (Rule-of-Thumb) |
|------|----------------|
| M1 | ~1000 |
| M2 | ~1100 |
| M3 | ~1290 |
| M4 | ~1600 |
| M5 | ~2000 |
| M5 Pro | ~2650-2850 |
| M4 Max | ~2870 |
| A18 Pro (Neo) | ~1165 |

> **Note on Disk scores:** SSD capacity directly affects disk benchmark results. Larger SSDs (512GB, 1TB+) have more NAND channels working in parallel, producing higher throughput than smaller SSDs (256GB). Disk scores are clamped (0.25x-4.0x vs baseline) to limit this effect, but comparisons across different SSD capacities should account for this hardware difference.

### AI Score (Separate)
The AI/ML score is reported **separately** from the Total Score (similar to Geekbench AI):
- **AI-CPU**: CoreML inference with CPU-only compute
- **AI-GPU**: CoreML inference with GPU acceleration
- **AI-Neural Engine**: CoreML inference with Neural Engine (when available)
- **AI-BNNS**: Accelerate framework matrix operations

*Note: Actual results may vary based on chassis, cooling, and configuration*

For detailed methodology, see the [Wiki](https://github.com/carlosacchi/apple-silicon-bench/wiki).

## Thermal States

- 🟢 **Nominal**: No throttling
- 🟡 **Fair**: Minor throttling possible
- 🟠 **Serious**: Significant throttling
- 🔴 **Critical**: Maximum throttling

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac

### Supported Chips

**M-series:**
M1, M1 Pro, M1 Max, M1 Ultra,
M2, M2 Pro, M2 Max, M2 Ultra,
M3, M3 Pro, M3 Max, M3 Ultra,
M4, M4 Pro, M4 Max,
M5, M5 Pro, M5 Max

**A-series:**
A18 Pro (MacBook Neo)

## Documentation

See the **[Wiki](https://github.com/carlosacchi/apple-silicon-bench/wiki)** for:
- [Scoring Methodology](https://github.com/carlosacchi/apple-silicon-bench/wiki/Scoring-Methodology) - How scores are calculated
- [Benchmark Details](https://github.com/carlosacchi/apple-silicon-bench/wiki/Benchmark-Details) - Technical details of each test
- [Advanced Profiling](https://github.com/carlosacchi/apple-silicon-bench/wiki/Advanced-Profiling) - PassMark-inspired deep analysis
- [FAQ](https://github.com/carlosacchi/apple-silicon-bench/wiki/FAQ) - Common questions and troubleshooting
- [Roadmap](https://github.com/carlosacchi/apple-silicon-bench/wiki/Roadmap) - Planned features

## Why Apple Silicon Bench?

| Feature | Apple Silicon Bench | Geekbench 6 | Cinebench |
|---------|---------------------|-------------|-----------|
| Open Source | Yes | No | No |
| Offline | Yes | Account required | Yes |
| Transparent Scoring | Yes | Closed | Closed |
| Thermal Monitoring | Yes | No | No |
| Binary Size | ~2MB | ~200MB | ~1GB |
| Price | Free | $15 (Pro) | Free |

## Contributing

Contributions welcome! See the [Wiki](https://github.com/carlosacchi/apple-silicon-bench/wiki) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) file.

## Author

**Carlo Sacchi** - [@carlosacchi](https://github.com/carlosacchi)

---

Made with Swift for Apple Silicon
