# Benchmark

tarn `361df3ff4` against upstream Ghostty `48dde97e0`, both ReleaseLocal.
2026-10-25, Apple M4, 10 cores, macOS 26.6.2.
One window, one surface; runs alternate between the apps; thresholds of `docs/spec.md` section 7. Input latency is not measured.

| Metric | tarn | upstream | Difference | Within threshold |
| --- | --- | --- | --- | --- |
| Startup, ms (median of 10) | 247.92 | 231.03 | +7.3% | no |
| Idle CPU, % (mean of 60 s) | 0.36 | 0.35 | +0.00 pp | yes |
| Memory RSS, MB (median of 5) | 115.17 | 112.16 | +2.7% | yes |
| Memory footprint, MB (median of 5) | 125.75 | 123.67 | +1.7% | yes |
| cat 100 MB, s (median of 5) | 0.32 | 0.30 | +6.6% | no |
