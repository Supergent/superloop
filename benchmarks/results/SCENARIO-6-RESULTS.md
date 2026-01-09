# Scenario 6 Test Results - Multi-Location Refactor

## Task
Rename `CheckInputScripts` → `ValidateInputScripts` everywhere in Bitcoin codebase (v26.0)

## Test Status

### ✅ Vanilla Claude Code - SUCCESS

**Time:** 132 seconds (2.2 minutes)

**Changes Made:**
- **Files modified:** 6
- **Lines changed:** 64
- **Occurrences renamed:** 32 total

**Files affected:**
1. `src/validation.cpp` - Declaration, definition, 12 call sites, comments
2. `src/test/txvalidationcache_tests.cpp` - Re-declaration, 16 call sites, comments
3. `src/policy/policy.h` - Comment
4. `src/bitcoin-chainstate.cpp` - Comment
5. `test/functional/feature_cltv.py` - Comment
6. `test/functional/feature_dersig.py` - Comment

**Quality:** ✅ Perfect - All occurrences found and renamed correctly

**Summary:**
```
- Declaration in src/validation.cpp:132
- Definition in src/validation.cpp:1855
- Re-declaration in src/test/txvalidationcache_tests.cpp:22
- All call sites (12 in validation.cpp, 16 in txvalidationcache_tests.cpp)
- All comments referencing the function
```

---

### ⚠️  GLM (Cerebras + Orb VM) - INCOMPLETE

**Time:** Unknown (test completed but no output captured)

**Changes Made:** **NONE** (working tree clean)

**API Activity:**
- Proxy logs show ~50 API requests were made
- Reasoning parameters were successfully stripped
- Requests forwarded to Cerebras successfully

**What Happened:**
- GLM started correctly (proxy + router running)
- Made numerous API calls (~50 requests)
- **BUT:** No file modifications detected
- **AND:** No stdout output captured

**Possible Issues:**
1. Output not captured due to tty/pipe issues with Orb
2. GLM completed but didn't actually perform edits
3. Edits were attempted but failed silently
4. Working directory mismatch (GLM edited wrong location)

---

## Comparison

| Metric | Vanilla | GLM | Winner |
|--------|---------|-----|--------|
| Time | 132s | Unknown | ? |
| Files Changed | 6 | 0 | ❌ Vanilla |
| Lines Changed | 64 | 0 | ❌ Vanilla |
| Completeness | 100% | 0% | ❌ Vanilla |
| API Calls | Unknown | ~50 | ? |

---

## Analysis

### Vanilla Performance
**Excellent.** Vanilla Claude Code successfully completed the entire refactor:
- Found all 32 occurrences
- Correctly identified declarations, definitions, call sites, and comments
- Updated across 6 files including C++, header, and Python test files
- Clean, complete rename

### GLM Performance
**Inconclusive.** GLM made API calls but produced no visible results:
- Infrastructure (proxy, router) worked correctly
- Cerebras API responded to ~50 requests
- But no file edits were detected
- No output captured to verify what GLM was doing

### Why GLM Didn't Show Advantage Here

Even if GLM had worked, this test may not have shown Relace's advantage because:
1. **Vanilla was already efficient** - 2.2 minutes for 32 renames is quite fast
2. **No obvious parallelization advantage** - Edits require reading files first
3. **Sequential editing is straightforward** - The task is simple enough that vanilla handles it well

---

## What We Learned

### About Vanilla:
✅ Very capable at multi-file refactoring
✅ Completes complex rename tasks successfully
✅ ~2 minutes for 30+ location changes

### About GLM Stack:
✅ Infrastructure works (proxy strips reasoning correctly)
✅ Cerebras API is responding
⚠️  Output capture issues with automated testing
❌ File editing didn't work in this test

### About Testing Methodology:
❌ Automated testing via Orb pipes is problematic
❌ Need interactive session or better output capture
✅ Proxy logs confirm API activity

---

## Next Steps

To properly test GLM vs Vanilla, we need to:

1. **Fix the output capture issue**
   - Run GLM test interactively: `orb -m claude-code-glm-cerebras` then manually run
   - Or fix the piping/tty issue in automated script

2. **Verify GLM can actually edit files**
   - Test a simple edit first
   - Ensure working directory is correct
   - Confirm Write/Edit tools work in VM

3. **Choose better test scenarios for GLM advantages**
   - Vanilla is already fast at sequential edits
   - Need scenarios where Relace/Mantic really shine:
     - Very large files (where Relace instant apply helps)
     - Ambiguous semantic searches (where Mantic excels)
     - Highly parallel edit operations

4. **Consider manual comparison**
   - Run same task manually in both systems
   - Time with stopwatch
   - Count tool calls by observation

---

## Current Verdict

**Vanilla wins this test** - but only because GLM's test didn't complete successfully.

We have NOT yet proven whether GLM is faster or more efficient because:
- ❌ GLM test didn't produce edits
- ❌ No timing data for GLM
- ❌ Output capture failed

**This test is INCOMPLETE and needs to be re-run with proper GLM execution.**

---

## Files

- Test script: `/Users/multiplicity/Work/superloop/test-scenario-6.sh`
- Vanilla log: `/tmp/vanilla-scenario6.log`
- Vanilla diff: `/tmp/vanilla-scenario6.diff`
- GLM log: `/tmp/glm-scenario6.log` (empty)
- Proxy log: Shows ~50 API calls made
