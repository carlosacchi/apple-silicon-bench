# Claude Code Guidelines for Apple Silicon Bench

## Project Overview

Native macOS benchmark tool for Apple Silicon (M1/M2/M3/M4) written in Swift. CLI-based with HTML report generation.

## Build & Run

```bash
# Build debug
swift build

# Build release
swift build -c release

# Run
.build/debug/osx-bench run
.build/release/osx-bench run --quick
```

## Project Structure

```
Sources/osx-bench/
├── main.swift              # CLI entry point (ArgumentParser)
├── Benchmarks/             # Individual benchmark implementations
│   ├── CPUSingleCoreBenchmark.swift
│   ├── CPUMultiCoreBenchmark.swift
│   ├── MemoryBenchmark.swift
│   └── DiskBenchmark.swift
├── Core/                   # Core logic
│   ├── BenchmarkRunner.swift   # Actor orchestrating benchmarks
│   ├── Results.swift           # Data models and scoring
│   ├── SystemInfo.swift        # System detection (sysctl)
│   └── ThermalMonitor.swift    # Thermal state tracking
└── Report/
    └── HTMLReportGenerator.swift
```

## Swift Best Practices

### General

- Use Swift Concurrency (async/await, actors) for parallel work
- Prefer value types (struct) over reference types (class) unless shared mutable state is needed
- Use `guard` for early exits, `if let` for optional binding
- Avoid force unwrapping (`!`) - use `guard let` or nil coalescing (`??`)

### Performance-Critical Code

- Use `@inlinable` sparingly and only for hot paths
- Prefer `ContiguousArray` over `Array` for numeric workloads
- Use `withUnsafeBufferPointer` for direct memory access
- Leverage Accelerate framework (vDSP, vForce) for vectorized operations
- Use `CFAbsoluteTimeGetCurrent()` for precise timing

### Memory Management

- Use `autoreleasepool` when creating many temporary objects in loops
- Prefer `Data` over `[UInt8]` for byte buffers
- Use `posix_memalign` for page-aligned allocations in benchmarks
- Always `free()` memory allocated with C functions

### File I/O

- Use `FileHandle` with `O_DIRECT` or `fcntl(F_NOCACHE)` to bypass cache for accurate disk benchmarks
- Clean up temporary files in `defer` blocks

### Error Handling

- Use `throws` for recoverable errors
- Provide meaningful error messages
- Don't catch errors just to print them - let them propagate

## Code Style

- 4 spaces indentation
- Opening braces on same line
- Use trailing closures when the closure is the last parameter
- Prefer `// MARK: -` for section organization
- Keep functions short and focused

## Git Workflow

### Commit Messages

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`
- Write in imperative mood: "Add feature" not "Added feature"
- Keep subject line under 72 characters

### Important Rules

- **DO NOT** include AI/bot attribution in commits (no "Co-Authored-By" with AI names)
- **DO NOT** include "Generated with" or similar AI tool references
- **DO NOT** mention Claude, GPT, or any AI assistant in commit messages
- Commits should appear as if written by a human developer
- Use standard git author configuration only

### Versioning

This project follows [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH):

**Version Format:** `X.Y.Z` where:
- **X (MAJOR)**: Breaking changes, incompatible API modifications
- **Y (MINOR)**: New features, backward-compatible additions
- **Z (PATCH)**: Bug fixes, minor improvements, backward-compatible

**When to bump:**

| Change Type | Version Bump | Examples |
|-------------|--------------|----------|
| Breaking API change | MAJOR (X.0.0) | Remove command, change output format |
| New feature | MINOR (X.Y.0) | Add `--duration` option, new benchmark type |
| Bug fix | PATCH (X.Y.Z) | Fix calculation error, typo fix |
| Refactoring (no behavior change) | PATCH | Code cleanup, performance optimization |
| Documentation only | PATCH | README updates, comments |
| Dependencies update | PATCH or MINOR | Security fix = PATCH, new capability = MINOR |

**Files to update on each release:**
1. `Package.swift` - `let version = "X.Y.Z"`
2. `Sources/osx-bench/Core/Version.swift` - `static let version = "X.Y.Z"`
3. `Sources/osx-bench/Core/Version.swift` - `static let releaseDate = "YYYY-MM-DD"`
4. `CHANGELOG.md` - Add new version section with changes (REQUIRED!)

**CHANGELOG.md format:**
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing features

### Fixed
- Bug fixes

### Security
- Security-related changes
```
Also add link at bottom: `[X.Y.Z]: https://github.com/carlosacchi/apple-silicon-bench/releases/tag/vX.Y.Z`

**Release process:**
```bash
# Use bump script or manually update version files
./scripts/bump-version.sh patch|minor|major

# Or manually:
# 1. Update version in Package.swift and Version.swift
# 2. Update releaseDate in Version.swift
# 3. Commit: git commit -m "chore: bump version to X.Y.Z"
# 4. Tag: git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
# 5. Push: git push origin main && git push origin vX.Y.Z
```

**Tag format:** Always use `v` prefix: `v1.0.0`, `v1.1.0`, `v1.1.1`

## Testing

Currently no test suite. When adding tests:
- Use XCTest framework
- Name tests descriptively: `test_benchmarkRunner_completesAllBenchmarks`
- Mock system calls where possible

## Dependencies

- `swift-argument-parser` - CLI parsing (only external dependency)
- Keep dependencies minimal for a benchmark tool

## Performance Considerations

- Warm-up runs before measurements
- Multiple iterations with averaging
- Quick mode reduces iterations for faster feedback
- Monitor thermal state to detect throttling

## HTML Report

- Self-contained HTML with inline CSS and Chart.js CDN
- Saved to `~/Desktop/OSX-Bench-Reports/`
- Dark theme with responsive design
