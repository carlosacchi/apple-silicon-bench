# Apple Silicon Bench

**A native macOS benchmark tool for Apple Silicon Macs (M1, M2, M3, M4, M5)**

[![Release](https://img.shields.io/github/v/release/carlosacchi/apple-silicon-bench)](https://github.com/carlosacchi/apple-silicon-bench/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)

A lightweight, native Swift benchmark tool designed specifically for Apple Silicon processors. Compare your M1, M2, M3, M4, M5 (and future chips) performance with comprehensive CPU, memory, and disk benchmarks.

## Features

- **CPU Single-Core Benchmark**: Integer, floating-point, SIMD (Accelerate framework), cryptography (AES-GCM), and compression tests
- **CPU Multi-Core Benchmark**: Parallel workload scaling across all P-cores and E-cores
- **Memory Benchmark**: Sequential read/write bandwidth, memory copy speed, and random access latency
- **Disk Benchmark**: Sequential and random I/O performance with cache bypass
- **Thermal Monitoring**: Real-time thermal state tracking during benchmarks
- **Beautiful HTML Reports**: Interactive charts and detailed breakdowns saved to Desktop
- **Lightweight Binary**: ~2MB standalone executable, no dependencies required

## Quick Start

### Download Binary

Download the latest release from the [Releases page](https://github.com/carlosacchi/apple-silicon-bench/releases).

```bash
# Download and extract
curl -LO https://github.com/carlosacchi/apple-silicon-bench/releases/latest/download/osx-bench-macos-arm64.tar.gz
tar -xzf osx-bench-macos-arm64.tar.gz
chmod +x osx-bench

# Run benchmark
./osx-bench run
```

### Build from Source

Requires Xcode 15+ or Swift 5.9+ toolchain.

```bash
git clone https://github.com/carlosacchi/apple-silicon-bench.git
cd apple-silicon-bench
swift build -c release
./.build/release/osx-bench run
```

## Usage

### Full Benchmark Suite

```bash
# Run all benchmarks (recommended for accurate results)
osx-bench run

# Quick mode - faster but less accurate
osx-bench run --quick
```

### Selective Benchmarks

```bash
# CPU only
osx-bench run --only cpu-single,cpu-multi

# Memory and disk only
osx-bench run --only memory,disk

# Single-core CPU only
osx-bench run --only cpu-single
```

### System Information

```bash
# View system info
osx-bench info

# Detailed system info
osx-bench info --detailed
```

### Export Results

```bash
# Export to JSON
osx-bench run --export results.json

# Offline mode (no future cloud features)
osx-bench run --offline
```

## Benchmark Categories

### CPU Single-Core

| Test | Description | Metric |
|------|-------------|--------|
| Integer | 64-bit integer arithmetic operations | ops/sec |
| Float | Double-precision floating-point | GFLOPS |
| SIMD | Accelerate framework vDSP operations | GFLOPS |
| Crypto | AES-256-GCM encryption | GB/s |
| Compression | LZFSE compress/decompress | MB/s |

### CPU Multi-Core

Same tests as single-core, executed in parallel across all CPU cores with efficiency scaling measurement.

### Memory

| Test | Description | Metric |
|------|-------------|--------|
| Read | Sequential memory read bandwidth | GB/s |
| Write | Sequential memory write bandwidth | GB/s |
| Copy | Memory copy (memcpy) performance | GB/s |
| Latency | Random access latency (pointer chase) | ns |

### Disk

| Test | Description | Metric |
|------|-------------|--------|
| Seq Read | Sequential file read | MB/s |
| Seq Write | Sequential file write | MB/s |
| Rand Read | 4KB random read IOPS | IOPS |
| Rand Write | 4KB random write IOPS | IOPS |

## Thermal Monitoring

The benchmark tracks macOS thermal state throughout the run:

- 🟢 **Nominal**: Normal operation, no throttling
- 🟡 **Fair**: Slightly warm, minor throttling possible
- 🟠 **Serious**: Hot, significant throttling active
- 🔴 **Critical**: Maximum throttling, severely impacted

If throttling is detected, results may be lower than optimal. Consider waiting for the system to cool down.

## HTML Report

After each benchmark run, a detailed HTML report is generated at:

```
~/Desktop/OSX-Bench-Reports/osx-bench-report-YYYY-MM-DD_HH-mm-ss.html
```

The report includes:
- System information (chip, cores, RAM, macOS version)
- Score breakdown with interactive charts
- Thermal progression timeline
- Detailed results for each benchmark category

## Scoring System

Scores are normalized against a baseline (M1 base chip = 1000 points per category):

- **CPU Single-Core**: 30% of total score
- **CPU Multi-Core**: 30% of total score
- **Memory**: 20% of total score
- **Disk**: 20% of total score

## Supported Systems

- **macOS**: 13.0 (Ventura) or later
- **Architecture**: Apple Silicon only (M1, M2, M3, M4, M5 family)
- **Processor Types**: MacBook Air, MacBook Pro, Mac mini, Mac Studio, Mac Pro, iMac

## Comparison Examples

Use this tool to compare different Apple Silicon configurations:

- M1 vs M1 Pro vs M1 Max vs M1 Ultra
- M2 vs M3 vs M4 vs M5
- Base vs Pro vs Max variants
- Different RAM configurations
- MacBook vs Mac Studio thermal performance

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Roadmap

- [ ] GPU benchmark (Metal compute shaders)
- [ ] Neural Engine benchmark (CoreML inference)
- [ ] Unified Memory bandwidth (CPU-GPU transfer)
- [ ] Power efficiency metrics
- [ ] Online leaderboard for community comparisons
- [ ] Historical tracking of your machine's performance

## Keywords

Apple Silicon benchmark, M1 benchmark, M2 benchmark, M3 benchmark, M4 benchmark, M5 benchmark, macOS performance test, Mac benchmark tool, Apple Silicon performance, M1 Pro benchmark, M1 Max benchmark, M2 Pro benchmark, M3 Pro benchmark, M4 Pro benchmark, M5 Pro benchmark, Mac CPU benchmark, Mac memory benchmark, Mac SSD benchmark, Apple chip comparison, ARM Mac benchmark, native macOS benchmark

---

Made with Swift for Apple Silicon
