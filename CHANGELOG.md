# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-01-02

### Added

- Extended system information with GPU and battery details
- New `--extended` flag for detailed system info (GPU, battery, disk)
- New `--sensitive` flag for Machine ID and other sensitive data
- Default `--brief` mode for basic system information
- GPU model, core count, and Metal version detection
- Battery cycle count, health, and charging status (MacBooks only)

### Changed

- `osx-bench info` now defaults to brief mode (basic system info)
- System info collection separated into privacy-conscious tiers

## [1.2.5] - 2026-01-01

### Security

- Added memory allocation validation against system RAM (CWE-770)
- Improved posix_memalign error handling with proper return code checks
- Added mlock/munlock success tracking to prevent invalid unlock calls

## [1.2.4] - 2026-01-01

### Security

- Hardened file permissions in disk benchmarks (0o600 instead of 0o644)
- Added O_NOFOLLOW flag to prevent symlink attacks (CWE-59)
- HTML escaping for dynamic content in reports to prevent XSS (CWE-79)
- Added SRI hash for Chart.js CDN integrity verification (CWE-829)
- Secure file permissions (0o700/0o600) for machine ID storage (CWE-312)

## [1.2.3] - 2025-12-31

### Fixed

- Total score normalization now uses benchmark presence (not score > 0)
- Failed benchmarks show "Failed" instead of being hidden
- Multi-core scoring scales with actual core count (not hardcoded 8)
- HTML report hides categories that weren't run (partial runs)
- Chart only shows benchmarks that were actually run

## [1.2.2] - 2025-12-31

### Fixed

- Scoring system: CPU reference units now match benchmark output (Mops/s, GFLOPS, MB/s)
- Partial runs (`--only`) now calculate total score using only selected benchmarks
- Failed tests (value = 0) are excluded from score averages

### Added

- Quick mode warning in score output ("scores may be less accurate")
- Partial run info in score output ("total based on selected tests")

## [1.2.1] - 2025-12-31

### Changed

- CLI output style: replaced box-drawing pipes with clean lines and dot-padding
- Improved terminal compatibility across different fonts and encodings

## [1.2.0] - 2025-12-31

### Added

- Disk information in `osx-bench info` command (model, capacity, type SSD/HDD)
- Disk info included in JSON exports and HTML reports

## [1.1.3] - 2025-12-31

### Fixed

- Chart.js loading in HTML report (removed SRI due to CDN hash instability)
- CLI banner text alignment for dynamic version length

## [1.1.2] - 2025-12-31

### Security

- Pin Chart.js to version 4.4.1 (supply-chain security)
- Remove machine ID from JSON exports (privacy protection)
- Use UUID-based temp directory for disk benchmarks (prevent symlink attacks)
- Replace `try!` with `do/catch` in CryptoKit calls (prevent crash/DoS)

### Fixed

- GitHub Actions CI workflow permissions

## [1.1.1] - 2025-12-31

### Fixed

- Dynamic copyright year (was hardcoded to 2024)
- Developer credits wording ("Designed and developed by")

### Added

- Release date field in version output
- Versioning guidelines in CLAUDE.md

## [1.1.0] - 2025-12-31

### Added

- `--duration` option to control test duration per benchmark category
- `--stress` flag for extended 60-second tests
- Duration-based benchmark loops (replaces fixed iteration counts)
- Roadmap section in README.md with versioned milestones (v1.2-v1.6)
- `xattr -cr` quarantine removal instruction in README

### Changed

- Default test duration: 10 seconds per category
- Quick mode duration: 3 seconds per category

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

[1.2.5]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.5
[1.2.4]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.4
[1.3.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.3.0
[1.2.5]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.5
[1.2.3]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.3
[1.2.2]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.2
[1.2.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.1
[1.2.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.0
[1.1.3]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.1.3
[1.1.2]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.1.2
[1.1.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.1.1
[1.1.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.1.0
[1.0.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.0.1
[1.0.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.0.0
