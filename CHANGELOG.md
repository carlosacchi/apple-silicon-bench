# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2024-12-31

### Fixed

- Ad-hoc code signing to reduce macOS Gatekeeper warnings
- Improved download instructions with `xattr -cr` for quarantine removal
- Centralized version management via Package.swift

### Added

- Version bump script (`scripts/bump-version.sh`)
- AppInfo enum for consistent version display across CLI and reports

## [1.0.0] - 2024-12-30

### Added

- **CPU Single-Core Benchmark**
  - Integer arithmetic operations (64-bit)
  - Floating-point operations (double precision)
  - SIMD operations using Apple Accelerate framework (vDSP)
  - Cryptography benchmark (AES-256-GCM via CryptoKit)
  - Compression benchmark (LZFSE)

- **CPU Multi-Core Benchmark**
  - Parallel execution of all CPU tests
  - Automatic detection of P-cores and E-cores
  - Thread scaling efficiency measurement

- **Memory Benchmark**
  - Sequential read bandwidth (page-aligned buffers)
  - Sequential write bandwidth
  - Memory copy performance (memcpy)
  - Random access latency (pointer chase algorithm)

- **Disk Benchmark**
  - Sequential read (128MB-512MB blocks)
  - Sequential write
  - Random read IOPS (4KB blocks)
  - Random write IOPS (4KB blocks)
  - Cache bypass using `fcntl(F_NOCACHE)`

- **Thermal Monitoring**
  - Real-time thermal state tracking
  - Visual indicators (green/yellow/orange/red)
  - Throttling detection and warnings
  - Thermal progression in HTML report

- **HTML Report Generation**
  - Beautiful dark theme with gradient accents
  - Interactive charts using Chart.js
  - System information display
  - Score breakdown by category
  - Thermal timeline visualization
  - Auto-saved to Desktop/OSX-Bench-Reports/

- **CLI Features**
  - `run` command with full benchmark suite
  - `--quick` mode for faster benchmarks
  - `--only` flag for selective benchmarks
  - `--export` for JSON output
  - `--offline` mode
  - `info` command for system information
  - `--detailed` flag for verbose system info

- **Scoring System**
  - Normalized scores (M1 base = 1000 points)
  - Weighted total score
  - Per-category breakdowns

### Technical Details

- Pure Swift implementation
- Apple Accelerate framework integration
- CryptoKit for hardware-accelerated encryption
- Swift Concurrency (async/await, TaskGroup)
- Actor-based benchmark runner
- ~2MB standalone binary

[1.0.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.0.1
[1.0.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.0.0
