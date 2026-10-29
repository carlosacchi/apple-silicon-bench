# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.4.x   | :white_check_mark: |
| < 2.4   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it by:

1. **Email**: Open an issue with `[SECURITY]` prefix (for non-critical issues)
2. **Private disclosure**: For critical vulnerabilities, contact the maintainer directly

We aim to respond within 48 hours and provide a fix within 7 days for critical issues.

---

## Security Measures Implemented

### v2.3.0
- Strict validation of `--only` and `--repeats` CLI input: unknown values now abort with an error instead of being silently ignored (CWE-20)
- Privacy notice corrected to match actual network access (Apple ML assets model download, Chart.js via jsDelivr) and to show where consent is stored
- Disk detection queries the physical store of the boot volume via `diskutil` (fixed argument list, no shell, stderr discarded)

### v1.2.5
- Memory allocation validation against system RAM (CWE-770)
- Proper `posix_memalign` return code checking
- `mlock`/`munlock` success tracking

### v1.2.4
- File permissions hardened to 0o600 (CWE-276)
- `O_NOFOLLOW` flag to prevent symlink attacks (CWE-59)
- HTML escaping for XSS prevention (CWE-79)
- SRI hash for Chart.js CDN integrity (CWE-829)
- Secure machine ID storage with 0o700/0o600 permissions (CWE-312)

### v1.1.2
- UUID-based temp directories to prevent symlink attacks
- Machine ID removed from JSON exports (privacy)
- Replaced `try!` with proper error handling in CryptoKit calls

---

## Known Limitations (By Design)

The following items were identified during security audits but are **intentionally not addressed** due to the nature of this application as a benchmarking tool:

### 1. Cryptographic Keys Not Explicitly Zeroed

**Status**: Accepted Risk
**CWE**: CWE-244 (Heap Inspection)

**Details**:
- `SymmetricKey` objects in crypto benchmarks are not explicitly zeroed after use
- Swift's ARC handles object deallocation, but memory may persist briefly

**Rationale**:
- Keys are randomly generated test keys with no real-world value
- Keys are short-lived (single benchmark operation)
- Zeroing would add overhead that distorts benchmark results
- CryptoKit handles internal memory security

**Risk Level**: Low (benchmark context only)

---

### 2. Memory Buffers Not Zeroed Before Free

**Status**: Accepted Risk
**CWE**: CWE-316 (Cleartext Storage in Memory)

**Details**:
- 256MB benchmark buffers are freed without explicit zeroing
- Test patterns (0x5A) may persist in freed memory

**Rationale**:
- Buffers contain synthetic test patterns, not sensitive data
- Zeroing 256MB would add ~100ms overhead per test
- This would significantly distort benchmark comparisons
- Other benchmark tools (sysbench, fio, Geekbench) follow the same approach

**Risk Level**: Very Low (no sensitive data involved)

---

### 3. Export Path Not Validated

**Status**: Accepted Risk
**CWE**: CWE-22 (Path Traversal)

**Details**:
- The `--export` flag accepts user-provided paths without validation
- User could specify paths outside expected directories

**Rationale**:
- This is a CLI tool run by the user with their own permissions
- Users already have full filesystem access
- Path traversal only affects locations the user can already write to
- Adding restrictions would limit legitimate use cases (e.g., exporting to network drives)

**Risk Level**: Low (user is the threat actor and victim)

---

### 4. Report Directory Uses Default Permissions

**Status**: Accepted Risk
**CWE**: CWE-732 (Incorrect Permission Assignment)

**Details**:
- `~/Desktop/OSX-Bench-Reports/` created with default umask
- On shared systems, reports may be readable by other users

**Rationale**:
- macOS is primarily a single-user system
- Benchmark reports don't contain sensitive information
- Users can adjust umask if needed for their environment

**Risk Level**: Very Low (informational data only)

---

## Security Architecture

### Data Flow

```
User Input (CLI) → Benchmark Runner → System APIs → Results
                                                      ↓
                                              HTML Report (local)
                                              JSON Export (optional)
```

### Trust Boundaries

1. **CLI Input**: Parsed by swift-argument-parser (trusted dependency)
2. **System APIs**: Direct syscalls for memory/disk benchmarks
3. **File Output**: Written to user-controlled paths only
4. **External Resources**: Chart.js loaded via CDN with SRI verification

### Dependencies

| Dependency | Version | Purpose | Security Notes |
|------------|---------|---------|----------------|
| swift-argument-parser | 1.3.0+ | CLI parsing | Apple-maintained, audited |
| Chart.js (CDN) | 4.4.1 | Report charts | SRI hash verified |

---

## Threat Model

### In Scope
- Local privilege escalation via benchmark tool
- Information disclosure through temp files
- Denial of service via resource exhaustion
- Supply chain attacks via dependencies

### Out of Scope
- Attacks requiring physical access
- Social engineering
- Network-based attacks (tool is offline)
- Attacks on the benchmark results themselves

---

## Audit History

| Date | Auditor | Findings | Resolution |
|------|---------|----------|------------|
| 2026-01-01 | Internal | 8 issues identified | 5 fixed, 3 accepted |
| 2026-10-16 | Internal | 1 issue (CLI input validation, GitHub #1) | 1 fixed in v2.3.0 |

---

## Contact

For security concerns, open an issue at:
https://github.com/carlosacchi/apple-silicon-bench/issues
