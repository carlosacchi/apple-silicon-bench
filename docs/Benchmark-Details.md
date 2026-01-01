# Benchmark Details

Technical details about each benchmark category.

## CPU Single-Core

Tests single-threaded CPU performance using various workloads.

### Integer Operations
- **What**: 64-bit integer arithmetic (add, multiply, divide, modulo)
- **How**: Tight loop performing mixed operations on Int64 values
- **Metric**: Millions of operations per second (Mops/s)
- **Relevance**: General-purpose computation, parsing, logic

### Floating-Point Operations
- **What**: Double-precision (64-bit) floating-point math
- **How**: Loop with multiply, divide, sqrt, trigonometric operations
- **Metric**: Millions of operations per second (Mops/s)
- **Relevance**: Scientific computing, 3D math, simulations

### SIMD (Accelerate Framework)
- **What**: Vectorized operations using Apple's vDSP
- **How**: Large array dot products and vector operations
- **Metric**: GFLOPS (billions of floating-point ops per second)
- **Relevance**: Signal processing, machine learning, audio/video

### Cryptography (CryptoKit)
- **What**: AES-256-GCM encryption
- **How**: Encrypt random data blocks using hardware AES
- **Metric**: MB/s throughput
- **Relevance**: Disk encryption, TLS, secure storage

### Compression (LZFSE)
- **What**: Apple's LZFSE compression algorithm
- **How**: Compress and decompress data buffers
- **Metric**: MB/s combined throughput
- **Relevance**: App bundles, system optimization, backups

## CPU Multi-Core

Same tests as single-core, executed in parallel across all CPU cores.

- Uses Swift `TaskGroup` for parallel execution
- Automatically detects P-cores and E-cores
- Measures thread scaling efficiency
- Score normalized for core count (see [Scoring Methodology](Scoring-Methodology.md))

## Memory

Tests unified memory subsystem performance.

### Sequential Read
- **What**: Linear memory read bandwidth
- **How**: Page-aligned buffer, sequential access pattern
- **Metric**: GB/s
- **Note**: Uses `mlock` to prevent paging

### Sequential Write
- **What**: Linear memory write bandwidth
- **How**: Fill buffer with sequential writes
- **Metric**: GB/s

### Copy
- **What**: Memory-to-memory copy speed
- **How**: `memcpy` between aligned buffers
- **Metric**: GB/s
- **Relevance**: Data movement, buffer operations

### Latency
- **What**: Random access latency
- **How**: Pointer-chase algorithm (defeats prefetcher)
- **Metric**: Nanoseconds (lower = better)
- **Relevance**: Cache efficiency, random data structures

## Disk

Tests SSD/storage performance with cache bypass.

### Setup
- Creates temporary files in system temp directory
- Uses `fcntl(F_NOCACHE)` to bypass filesystem cache
- Uses `O_NOFOLLOW` to prevent symlink attacks
- Cleans up files after benchmark

### Sequential Read
- **What**: Large file read throughput
- **How**: Read 4MB chunks from 512MB file (128MB in quick mode)
- **Metric**: MB/s

### Sequential Write
- **What**: Large file write throughput
- **How**: Write 4MB chunks to 512MB file
- **Metric**: MB/s

### Random Read
- **What**: Small random read IOPS
- **How**: 4KB reads at random offsets in 256MB file
- **Metric**: IOPS (I/O operations per second)
- **Operations**: 5000 (1000 in quick mode)

### Random Write
- **What**: Small random write IOPS
- **How**: 4KB writes at random offsets
- **Metric**: IOPS
- **Operations**: 5000 (1000 in quick mode)

### Test Parameters

| Parameter | Quick Mode | Normal Mode |
|-----------|------------|-------------|
| Sequential file size | 128 MB | 512 MB |
| Sequential chunk size | 4 MB | 4 MB |
| Random file size | 256 MB | 256 MB |
| Random block size | 4 KB | 4 KB |
| Random operations | 1,000 | 5,000 |

## GPU (Metal)

Tests integrated GPU using Metal compute shaders.

### Technical Details
- Metal shaders compiled at runtime (SPM compatible)
- No external shader files or `.metallib` bundles
- Synthetic test data generated procedurally
- Measures actual GPU execution time

### Compute (Matrix Multiplication)
- **What**: Dense matrix multiply
- **How**: 2048×2048 float matrices (1024 in quick mode)
- **Metric**: GFLOPS
- **Formula**: 2×N³ FLOPS per multiply
- **Relevance**: ML inference, scientific computing

### Particles Simulation
- **What**: N-body physics simulation
- **How**: 1M particles with gravity/collision (100K in quick mode)
- **Metric**: Million particles per second (Mparts/s)
- **Relevance**: Games, simulations, physics engines

### Gaussian Blur
- **What**: 5×5 convolution kernel
- **How**: 4096×4096 texture (2048 in quick mode)
- **Metric**: Megapixels per second (MP/s)
- **Relevance**: Image processing, video effects

### Edge Detection (Sobel)
- **What**: Sobel edge detection filter
- **How**: Same texture size as blur
- **Metric**: Megapixels per second (MP/s)
- **Relevance**: Computer vision, feature detection

### Test Sizes

| Test | Quick Mode | Normal Mode |
|------|------------|-------------|
| Matrix | 1024×1024 | 2048×2048 |
| Particles | 100,000 | 1,000,000 |
| Image | 2048×2048 | 4096×4096 |

## Thermal Monitoring

Real-time thermal state tracking during benchmarks.

### States
| State | Meaning | Impact |
|-------|---------|--------|
| 🟢 Nominal | Normal operation | No throttling |
| 🟡 Fair | Slightly warm | Minor throttling possible |
| 🟠 Serious | Hot | Significant throttling |
| 🔴 Critical | Maximum temperature | Severe throttling |

### API
Uses `ProcessInfo.processInfo.thermalState` (public macOS API).

### Interpretation
- If throttling occurs, results may be lower than optimal
- Consider cooling or waiting before re-running
- Use `--stress` mode to intentionally trigger throttling for sustained performance testing

## Duration Modes

| Mode | Flag | Duration | Use Case |
|------|------|----------|----------|
| Quick | `--quick` | ~3s/test | Fast iteration |
| Normal | (default) | 10s/test | Standard benchmarks |
| Custom | `-d N` | N seconds | Specific needs |
| Stress | `--stress` | 60s/test | Thermal analysis |
