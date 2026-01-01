# Scoring Methodology

This document explains how Apple Silicon Bench calculates benchmark scores.

## Overview

Each benchmark category produces a **normalized score** where:
- **1000 points** = M1 base chip performance (baseline)
- **Higher scores** = better performance
- **Lower scores** = worse performance (or older hardware)

## Geometric Mean Formula

We use **geometric mean of ratios** instead of arithmetic mean. This approach:
- Prevents outliers from dominating the score
- Properly handles metrics with different units (GFLOPS, GB/s, ns, IOPS)
- Produces mathematically sound comparisons

### Category Score Calculation

For each sub-test *i* in a category:

1. **Calculate ratio** *rᵢ*:
   - Higher-is-better metrics: `rᵢ = value / baseline`
   - Lower-is-better metrics (latency): `rᵢ = baseline / value`

2. **Compute geometric mean**:
   ```
   CategoryScore = 1000 × exp(Σ ln(rᵢ) / n)
   ```
   Where *n* is the number of sub-tests.

### Total Score Calculation

The total score is a weighted average of category scores:

| Category | Weight |
|----------|--------|
| CPU Single-Core | 25% |
| CPU Multi-Core | 25% |
| Memory | 15% |
| Disk | 15% |
| GPU | 20% |

```
TotalScore = Σ (CategoryScore × Weight)
```

For partial runs (using `--only`), weights are normalized to sum to 100%.

## Baseline Reference Values (M1)

These values represent typical M1 base chip performance:

### CPU Single-Core
| Test | Baseline | Unit |
|------|----------|------|
| Integer | 38 | Mops/s |
| Float | 32 | Mops/s |
| SIMD | 8 | GFLOPS |
| Crypto | 1500 | MB/s |
| Compression | 500 | MB/s |

### Memory
| Test | Baseline | Unit | Direction |
|------|----------|------|-----------|
| Read | 1.5 | GB/s | Higher = Better |
| Write | 1.2 | GB/s | Higher = Better |
| Copy | 26 | GB/s | Higher = Better |
| Latency | 170 | ns | Lower = Better |

### Disk
| Test | Baseline | Unit |
|------|----------|------|
| Sequential Read | 14000 | MB/s |
| Sequential Write | 1100 | MB/s |
| Random Read | 22000 | IOPS |
| Random Write | 5700 | IOPS |

### GPU (Metal)
| Test | Baseline | Unit |
|------|----------|------|
| Compute (Matrix) | 150 | GFLOPS |
| Particles | 290 | Mparts/s |
| Blur | 1700 | MP/s |
| Edge Detection | 4300 | MP/s |

## Why Geometric Mean?

### Problem with Arithmetic Mean

Consider two tests with different scales:
- Test A: 100 GFLOPS (baseline: 100) → ratio = 1.0
- Test B: 1000 MB/s (baseline: 500) → ratio = 2.0

**Arithmetic mean**: (1.0 + 2.0) / 2 = 1.5 → Score: 1500

If Test B doubles while Test A halves:
- Test A: 50 GFLOPS → ratio = 0.5
- Test B: 2000 MB/s → ratio = 4.0

**Arithmetic mean**: (0.5 + 4.0) / 2 = 2.25 → Score: 2250

This incorrectly suggests overall improvement despite Test A being much worse.

### Geometric Mean Solution

Same scenario:
- **Geometric mean**: exp((ln(0.5) + ln(4.0)) / 2) = exp(0.347) = 1.41 → Score: 1414

The geometric mean correctly shows that the tradeoff is roughly neutral.

## Handling Failed Tests

- Tests with `value = 0` are excluded from scoring
- This prevents a single failed test from zeroing the entire category
- The category score is based on successful tests only

## Quick Mode vs Normal Mode

Quick mode (`--quick`) uses shorter test durations:
- Results may have higher variance
- Scores are still valid but "may be less accurate" (warning shown)
- Useful for rapid iteration during development

## Multi-Core Scaling

The CPU Multi-Core score accounts for different core counts:

```
multiReference = singleCoreBaseline × 8 × (actualCores / 8)
```

This normalizes scores so:
- An 8-core M1 gets ~1000 when performing at baseline
- A 10-core M1 Pro is compared fairly against its expected scaling
- A 4-core system isn't unfairly penalized

## Disk Benchmark Notes

Disk performance varies significantly by:
- SSD model and generation
- Available storage space
- macOS caching behavior

We use `F_NOCACHE` to bypass the filesystem cache, but results may still vary between runs.

## Thermal Impact

Thermal throttling affects scores:
- Monitor the thermal indicator during benchmarks
- If throttling occurs (yellow/orange/red), scores may be lower than optimal
- Use `--stress` mode to measure sustained (throttled) performance

## Comparing Results

When comparing scores across systems:
1. Use the same benchmark version
2. Run in normal mode (not quick) for accuracy
3. Ensure similar thermal conditions
4. Compare category scores, not just totals
5. Consider that disk scores vary by SSD model

## Source Code

The scoring implementation is in:
- `Sources/osx-bench/Core/Results.swift` - `BenchmarkScorer` struct
- `calculateGeometricMeanScore()` function

## References

- [Geometric Mean on Wikipedia](https://en.wikipedia.org/wiki/Geometric_mean)
- [SPEC CPU Benchmark Methodology](https://www.spec.org/cpu2017/Docs/overview.html)
- [Geekbench Scoring (for comparison)](https://www.geekbench.com/doc/geekbench5-compute-workloads.pdf)
