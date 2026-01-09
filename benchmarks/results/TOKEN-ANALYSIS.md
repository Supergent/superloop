# Token Usage Analysis - GLM vs Vanilla

## 🎯 Test Summary

**Task:** Rename `CheckInputScripts` → `ValidateInputScripts` in Bitcoin v26.0

---

## 📊 Raw Token Counts

### Vanilla Claude Code
```
Input tokens (fresh):        231
Cache read tokens:       1,027,728
Cache creation tokens:     146,555
Output tokens:              7,828
─────────────────────────────────
Total input:           1,174,514
Total output:              7,828
Grand total:           1,182,342 tokens
```

### GLM (Cerebras in Orb VM)
```
Input tokens (fresh):      163,952
Cache read tokens:         743,560
Cache creation tokens:           0
Output tokens:              18,216
─────────────────────────────────
Total input:             907,512
Total output:             18,216
Grand total:             925,728 tokens
```

---

## 📉 Token Efficiency Comparison

| Metric | Vanilla | GLM | Difference |
|--------|---------|-----|------------|
| **Fresh Input** | 231 | 163,952 | +163,721 (GLM used MORE) |
| **Cache Read** | 1,027,728 | 743,560 | -284,168 (GLM used LESS) |
| **Cache Write** | 146,555 | 0 | -146,555 (GLM used LESS) |
| **Output** | 7,828 | 18,216 | +10,388 (GLM produced MORE) |
| **Total** | 1,182,342 | 925,728 | **-256,614 (GLM 21.7% less)** |

---

## 💰 Cost Analysis

### Using Claude Sonnet 4.5 Pricing
- **Input (fresh):** $3 per million tokens
- **Input (cached):** $0.30 per million tokens (90% discount)
- **Cache write:** $3.75 per million tokens
- **Output:** $15 per million tokens

### Vanilla Cost
```
Fresh input:     231 × $3.00  / 1M = $0.0007
Cache read: 1,027,728 × $0.30  / 1M = $0.3083
Cache write:  146,555 × $3.75  / 1M = $0.5496
Output:        7,828 × $15.00 / 1M = $0.1174
────────────────────────────────────────────
Total: $0.98
```

### GLM Cost (Cerebras Pricing)
**Note:** Using estimated Cerebras pricing (~$2-2.75/1M tokens)

Assuming **$2.50 per million tokens** (averaged):
```
Fresh input: 163,952 × $2.50 / 1M = $0.4099
Cache read:  743,560 × $2.50 / 1M = $1.8589
Output:       18,216 × $2.50 / 1M = $0.0455
────────────────────────────────────────────
Total: $2.31
```

**GLM cost more** ($2.31 vs $0.98) but was **5.9x faster**!

---

## 🔍 Deep Dive: Why The Differences?

### 1. Fresh Input Tokens (GLM used 163k MORE)

**Vanilla:** 231 tokens
- Very efficient prompt caching
- Most context loaded from cache

**GLM:** 163,952 tokens
- Loaded more fresh context each turn
- Possibly less aggressive caching
- OR different cache behavior in Cerebras/router

**Impact:** GLM sent more fresh data but completed task faster

---

### 2. Cache Read Tokens (GLM used 284k LESS)

**Vanilla:** 1,027,728 tokens from cache
- Heavy cache utilization
- Read cached context repeatedly

**GLM:** 743,560 tokens from cache
- 28% less cache reading
- More efficient cache usage OR different caching strategy

**Impact:** GLM read cache less but was still faster

---

### 3. Cache Creation (GLM created ZERO)

**Vanilla:** 146,555 tokens written to cache
- Created new cache entries during execution

**GLM:** 0 tokens written
- No cache creation OR Cerebras handles caching differently
- Router may not report cache writes the same way

**Impact:** Vanilla paid cache write costs

---

### 4. Output Tokens (GLM produced 10k MORE)

**Vanilla:** 7,828 output tokens
- Concise responses
- Completed in 132 seconds

**GLM:** 18,216 output tokens (2.3x more)
- More verbose output OR different response style
- Completed in 22 seconds (5.9x faster)

**Impact:** GLM produced more output but MUCH faster

---

## 🎯 Key Insights

### 1. **Speed vs Token Efficiency Trade-off**

GLM prioritized SPEED over token efficiency:
- Used 21.7% fewer total tokens
- But completed 5.9x faster
- Cost per second: Vanilla $0.0074/s, GLM $0.1050/s

### 2. **Different Caching Strategies**

- Vanilla: Heavy cache read (87% of input from cache)
- GLM: More balanced (82% from cache)
- GLM created no new caches (different architecture?)

### 3. **Output Verbosity**

GLM produced 2.3x more output:
- Possibly more detailed responses
- OR different response formatting
- Still completed task correctly

### 4. **ROI Analysis**

**For time-sensitive tasks:**
- GLM: $2.31 for 22 seconds = $0.105/sec
- Vanilla: $0.98 for 132 seconds = $0.007/sec

**For a developer at $200/hour ($3.33/min):**
- Vanilla: 132s = $7.33 developer time + $0.98 API = **$8.31 total**
- GLM: 22s = $1.22 developer time + $2.31 API = **$3.53 total**

**GLM saves $4.78 per task (58% total cost reduction when including developer time!)**

---

## 🏆 Final Token Verdict

### Token Efficiency Winner: **Vanilla** (21.7% fewer tokens)

### Cost Efficiency Winner: **GLM** (58% lower total cost including developer time)

### Time Efficiency Winner: **GLM** (5.9x faster)

### Best Overall: **GLM**

**Why:** Even though GLM used more API cost ($2.31 vs $0.98), the 5.9x speedup means:
- Developer saves 110 seconds (1.8 minutes)
- Total cost savings of $4.78 per task
- Higher throughput = more tasks completed per day

---

## 📈 Scaling Impact

### For 10 refactors/week:

**Vanilla:**
- Time: 1,320 seconds = 22 minutes
- API cost: $9.80
- Developer time: $73.30
- **Total: $83.10**

**GLM:**
- Time: 222 seconds = 3.7 minutes
- API cost: $23.10
- Developer time: $12.20
- **Total: $35.30**

**Weekly savings with GLM: $47.80 (58% reduction)**

**Annual savings: $2,485**

---

## 🎯 Conclusion

**GLM uses tokens differently than vanilla:**
1. More fresh input (less cache reliance)
2. More output tokens (more verbose?)
3. Overall 21.7% fewer total tokens
4. 2.4x higher API cost ($2.31 vs $0.98)

**BUT the speed advantage (5.9x) dominates:**
- Total cost (API + developer time) is 58% LOWER with GLM
- Real productivity gain from faster iteration
- Higher quality developer experience (less waiting)

**Recommendation: Use GLM for time-sensitive refactoring tasks where speed matters more than minimizing API costs.**

---

## Raw Data Sources

- **Vanilla:** `~/.claude/projects/-private-tmp-bitcoin-benchmark/ff426ede-1f25-4d78-85b8-99c98c1dd230.jsonl`
- **GLM:** `/home/multiplicity/.claude/projects/-Users-multiplicity-Work-bitcoin-test/8eb2a93a-b76c-4281-a634-9fbdbda38248.jsonl` (in Orb VM)
- **API calls:** 36 API calls for GLM session
