# Load Test Scripts

k6 scripts for benchmarking (T20, T21, T22):

- User journey script (feed, wait, post, like)
- Raw throughput test (/feed max RPS)
- Limit-search runner (doubling + bisection, 5-min confirmation, 3 repeats)
- Outputs `results/<run>/summary.json` with documented schema