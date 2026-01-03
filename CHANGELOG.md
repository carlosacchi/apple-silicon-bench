# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.4] - 2026-01-03

### Fixed

- Build error from missing return in INCOMPLETE score formatting

## [2.1.3] - 2026-01-03

### Added

- Advanced profiling JSON export (`advanced_profiles.json`) alongside standard JSON export
- Plausibility checks in HTML report for unusually high disk or memory throughput

### Changed

- Advanced disk profile section now includes explicit test parameters and cache/sync details
- Scaling cliff detection now reports significant efficiency drops instead of a binary threshold
- Benchmark categories with invalid subtests are marked INCOMPLETE and excluded from aggregate scoring

### Fixed

- Prevented `inf` values in memory block-size sweep by using adaptive timing and warmup passes

## [2.1.2] - 2026-01-03

### Changed

- Clarified advanced profiling terminology (stride throughput vs latency, cache boundaries)
- Documented disk cache bypass caveats and I/O volumes for advanced QD tests
- Updated advanced profiling report label to "Stride Throughput Sweep"

## [2.1.1] - 2026-01-03

### Fixed

- **GPU Benchmark Segmentation Fault**: Fixed crash on large textures (4096x4096)
  - Root cause: 64MB pixel array allocated on stack exceeded 8MB stack limit
  - Fix: Allocate texture data on heap using `UnsafeMutablePointer`
  - Also made noise pattern deterministic for reproducibility

## [2.1.0] - 2026-01-03

### Added

- **Advanced Profiling Mode** (`--advanced` flag)
  - Memory Profile: stride sweep + block-size sweep for cache boundary detection
  - Disk Profile: Queue Depth (QD) matrix for parallelism analysis
  - CPU Scaling: thread sweep for efficiency metric
  - Inspired by PassMark methodology
- **Version-aware Privacy Consent**
  - Consent now stored with version number
  - Re-asks consent on MINOR or MAJOR version upgrades
  - PATCH upgrades do not re-ask (same MAJOR.MINOR = consent valid)
- New wiki page: Advanced Profiling methodology documentation

### Changed

- HTML report now includes Advanced Profiling section with detailed tables
- CLI shows advanced profile summary with cache boundaries, optimal QD, scaling efficiency

### Technical Details

- Memory stride sweep: 8B to 4KB strides to stress spatial locality
- Memory block-size sweep: 4KB to 128MB to detect L1/L2/L3/DRAM transitions
- Disk QD matrix: QD1 to QD32 for read/write IOPS analysis
- CPU thread sweep: 1 to max cores for scaling efficiency calculation
- Scaling efficiency = (actual throughput) / (single-thread × thread count) × 100%

## [2.0.3] - 2026-01-04

### Fixed

- **HTML Report AI Score Position**: Moved AI/ML Score section after AI/ML benchmark section
  - Previously appeared before all benchmarks
  - Now appears immediately after AI/ML results for better logical flow
- **HTML Report Color Contrast**: Fixed unreadable light blue text on light background
  - Changed from light blue gradient background to dark background with cyan accents
  - Improved text readability with proper contrast ratios

## [2.0.2] - 2026-01-03

### Fixed

- **Model compilation without Xcode**: Use `MLModel.compileModel()` instead of `coremlcompiler`
  - No longer requires Xcode Command Line Tools
  - Works on any macOS 13+ system with CoreML framework

## [2.0.1] - 2026-01-03

### Changed

- **Model integrity verification**: Added SHA256 hash check for downloaded model
  - Ensures reproducible benchmarks with fixed model version
  - Model hash: `cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144`
  - MobileNetV2 from Apple ML assets (last modified: 2019-11-05)

## [2.0.0] - 2026-01-03

### Added

- **AI/ML Benchmark** - New benchmark category for Neural Engine and CoreML inference
  - CoreML CPU inference test (images per second)
  - CoreML GPU inference test (images per second)
  - CoreML Neural Engine inference test (images per second)
  - BNNS matrix operations test (GFLOPS via Accelerate framework)
- **AI Score is separate from Total Score** (like Geekbench AI)
  - Total Score remains: CPU-Single, CPU-Multi, Memory, Disk, GPU
  - AI Score: geometric mean of CPU/GPU/Neural Engine/BNNS tests
- **Model download system** for CoreML models
  - Automatic download from Apple's ML assets (`ml-assets.apple.com`)
  - Model compiled locally using `coremlcompiler` for your device
  - Cache in `~/Library/Application Support/osx-bench/models/`
  - `--model-path` option for custom local models
  - `--offline` flag to skip AI benchmark without download
- New CLI options: `--only ai`, `--only ml`, `--only neural`, `--only coreml`
- **First-run privacy consent prompt**
  - Displays privacy policy summary on first launch
  - Links to full policy at GitHub wiki
  - User must accept (y/n) to continue
  - Acceptance stored in `~/Library/Application Support/osx-bench/`
- Privacy policy wiki page with full disclosure

### Changed

- This is a **MAJOR** version bump (v2.0.0) due to new benchmark category
- HTML report now includes separate AI/ML score section with teal gradient
- CLI output shows AI score in separate section below Total Score

### Technical Details

- Uses CoreML with configurable compute units (.cpuOnly, .cpuAndGPU, .all)
- Neural Engine engaged via `.all` compute units when available
- BNNS matmul uses vDSP from Accelerate framework
- Warmup: 5 iterations (quick) / 20 iterations (full) before measurement
- Duration-based testing with minimum 5 iterations per compute unit

## [1.4.1] - 2026-01-03

### Fixed

- **Disk benchmark cache leak**: Random read was hitting filesystem cache
  - Increased random file size to 1GB (full) / 512MB (quick) to exceed cache
  - Apply F_NOCACHE BEFORE writing test files (not just on read)
  - Results now stable and reproducible

### Changed

- **Disk baselines recalibrated** to real M1 values with strict cache bypass:
  - Seq Read: 2180 MB/s (was 3356 - NovaBench includes cache)
  - Seq Write: 700 MB/s (was 3279 - with F_FULLFSYNC)
  - Rand Read: 43 MB/s (was 166 - true random from 1GB file)
  - Rand Write: 17 MB/s (was 761 - with final sync)
- Our tool now measures **actual disk performance**, not cache throughput
- This makes scores more meaningful for real-world workloads

### Technical Details

- Random tests now use 1GB file (full) / 512MB (quick) to exceed unified memory cache
- F_NOCACHE applied to write operations to prevent cache population
- Disk scores should now be stable across runs (~1000 on M1)

## [1.4.0] - 2026-01-02

### Added

- **NovaBench-compatible disk benchmark patterns** for improved comparability
  - Sequential I/O: 4MB blocks with cache bypass
  - Random I/O: 4KB blocks, QD1 (single operation) pattern
  - Matches industry-standard benchmark methodology

### Changed

- **Disk benchmark output**: All tests now report MB/s consistently
  - Random tests converted from IOPS to MB/s (IOPS × 4KB / 1MB)
  - Enables direct comparison with NovaBench and other tools
- **Baseline values updated** to NovaBench M1 reference measurements:
  - Seq Read: 3356 MB/s, Seq Write: 3279 MB/s
  - Rand Read: 166 MB/s, Rand Write: 761 MB/s
- Increased quick mode file size to 256MB (was 128MB) for more stable results
- Sequential tests now sync file before reading (F_FULLFSYNC)

### Technical Details

- Sequential: 4MB blocks, cache bypass via `F_NOCACHE`, sync via `F_FULLFSYNC`
- Random: 4KB blocks, QD1 pattern (one I/O at a time), cache bypass

## [1.3.2] - 2026-01-02

### Changed

- **Baseline calibration**: Re-calibrated all reference values from median of 5 real M1 runs
  - CPU Single-Core: Integer, Float, SIMD, Crypto, Compression
  - CPU Multi-Core: Added dedicated multi-core baselines (not scaled from single)
  - Memory: Read, Write, Copy, Latency
  - Disk: Sequential Read/Write, Random Read/Write IOPS
  - GPU: Compute, Particles, Blur, Edge detection
- M1 base chip now correctly scores ~1000 in each category
- Other Apple Silicon chips score proportionally (M2 ~1100, M3 ~1290, M4 ~1600)

### Added

- **Ratio clamping for Disk scores**: Clamp ratios to 0.25-4.0 range
  - Prevents cache effects from producing unrealistic scores
  - Handles SSD capacity variance (256GB vs 1TB have different speeds)
  - More stable scores across different volume states

### Fixed

- CPU Multi-Core scoring: Now uses dedicated multi-core baselines instead of
  incorrectly scaling single-core values by core count

## [1.3.1] - 2026-01-01

### Changed

- **Scoring algorithm**: Switched from arithmetic mean to geometric mean of ratios
  - Prevents outliers from dominating category scores
  - Properly handles metrics with different units (GFLOPS, GB/s, ns)
  - Lower-is-better metrics (latency) correctly inverted
- Re-calibrated baseline reference values from real M1 measurements

### Added

- Documentation wiki in `docs/` folder:
  - Scoring Methodology - detailed explanation of score calculation
  - Benchmark Details - technical details of each test
  - FAQ - common questions and troubleshooting

## [1.3.0] - 2026-01-01

### Added

- **GPU Benchmark (Metal)** - New benchmark category for Apple Silicon GPUs
  - Compute shader test (matrix multiplication) - measures GFLOPS
  - Particle simulation test - measures millions of particles per second
  - Gaussian blur test (5x5 kernel) - measures megapixels per second
  - Sobel edge detection test - measures megapixels per second
- GPU score included in total score calculation (20% weight)
- GPU results in HTML report with purple color scheme
- `--only gpu` and `--only metal` support for running GPU benchmark alone

### Changed

- Adjusted scoring weights: CPU-Single 25%, CPU-Multi 25%, Memory 15%, Disk 15%, GPU 20%
- Metal shaders compiled at runtime using inline source (SPM compatible)

## [1.2.7] - 2026-01-02

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

[2.1.4]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.1.4
[2.1.3]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.1.3
[2.1.2]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.1.2
[2.1.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.1.1
[2.1.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.1.0
[2.0.3]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.0.3
[2.0.2]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.0.2
[2.0.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.0.1
[2.0.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v2.0.0
[1.4.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.4.1
[1.4.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.4.0
[1.3.2]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.3.2
[1.3.1]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.3.1
[1.3.0]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.3.0
[1.2.7]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.7
[1.2.5]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.5
[1.2.4]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/v1.2.4
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
