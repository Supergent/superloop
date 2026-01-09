# Reasoning Parameter Fix - Working Solution

**Problem:** Claude Code Router v2.0.0 has a built-in "reasoning" transformer that adds a `reasoning` parameter to all requests. Cerebras API (OpenAI format) doesn't support this parameter, causing 422 errors.

**Root Cause:** The router's built-in reasoning transformer runs BEFORE custom transformers, and there's no working configuration option to disable it.

---

## ❌ Failed Attempts

We tried multiple approaches that did NOT work:

### 1. Config Workarounds (All Failed)
```json
// FAILED: These config options are ignored by router v2.0.0
{
  "reasoning": {"effort": null, "max_tokens": null},
  "disabledTransformers": ["reasoning", "forcereasoning"],
  "transformers": {"reasoning": false, "forcereasoning": false}
}
```

### 2. Environment Variable (Failed)
```bash
# FAILED: Claude Code ignores this
export MAX_THINKING_TOKENS=0
```

### 3. Custom Transformer Modifications (Failed)
```javascript
// FAILED: Custom transformer runs AFTER built-in reasoning transformer
delete anthropic.reasoning;
delete anthropic.thinking;
```

**Why these failed:** The router's transformer pipeline is:
```
1. Built-in transformers (reasoning, forcereasoning, etc.) ← Adds reasoning here
2. Custom provider transformers                            ← Too late to remove it!
3. Forward to API                                          ← Cerebras rejects
```

---

## ✅ Working Solution: Local Proxy

**Architecture:**
```
Claude Code
  ↓
Claude Code Router (adds reasoning parameter)
  ↓
Local Proxy on port 8080 (STRIPS reasoning parameter)
  ↓
Cerebras API (receives clean request, no errors!)
```

### Implementation Files

**1. Proxy Script: `~/cerebras-proxy.js`**
```javascript
#!/usr/bin/env node
const http = require("http");
const https = require("https");

const PORT = 8080;
const CEREBRAS_API_KEY = process.env.CEREBRAS_API_KEY;

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  let body = "";
  req.on("data", chunk => { body += chunk.toString(); });

  req.on("end", () => {
    try {
      const requestData = JSON.parse(body);

      // CRITICAL: Strip reasoning parameter
      delete requestData.reasoning;
      delete requestData.thinking;

      const requestBody = JSON.stringify(requestData);
      const contentLength = Buffer.byteLength(requestBody);

      // Forward to Cerebras
      const options = {
        hostname: "api.cerebras.ai",
        port: 443,
        path: req.url,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": contentLength,
          "Authorization": `Bearer ${CEREBRAS_API_KEY}`,
        }
      };

      const proxyReq = https.request(options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
      });

      proxyReq.on("error", (error) => {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Proxy error", details: error.message }));
      });

      proxyReq.write(requestBody);
      proxyReq.end();

    } catch (error) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid JSON" }));
    }
  });
});

server.listen(PORT, () => {
  console.error(`[PROXY] Listening on http://localhost:${PORT}`);
});
```

**2. Router Config: `~/.claude-code-router/config.json`**
```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "http://localhost:8080/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": ["zai-glm-4.7", "claude-haiku-4-5-20251001", ...],
      "transformer": {
        "request": "...cerebras-transformer.js::transformRequest",
        "response": "...cerebras-transformer.js::transformResponse",
        "streamChunk": "...cerebras-transformer.js::transformStreamChunk"
      }
    }
  ],
  "Router": {
    "default": "cerebras,zai-glm-4.7"
  }
}
```

**Key change:** `api_base_url` points to `localhost:8080` instead of `api.cerebras.ai`

**3. Startup Script: `~/start-claude-isolated.sh`**
```bash
#!/bin/bash
source ~/.bashrc

# Kill existing processes
pkill -f cerebras-proxy.js 2>/dev/null
pkill -f ccr 2>/dev/null
sleep 2

# Start proxy
node ~/cerebras-proxy.js > /tmp/cerebras-proxy.log 2>&1 &
sleep 2

# Start router
ccr start &
sleep 3
eval "$(ccr activate)"

# Start Claude Code
cd ~/vm-projects/superloop
claude
```

---

## Verification

**Check proxy logs:**
```bash
tail -f /tmp/cerebras-proxy.log
```

**Expected output:**
```
[PROXY] Stripped reasoning/thinking, forwarding request...
[PROXY] Request keys: [ 'messages', 'model', 'max_tokens', 'stream' ]
```

**No `reasoning` key = Success!** ✅

---

## Why This Works

1. **Router adds reasoning** - Built-in transformer runs first
2. **Proxy strips reasoning** - Intercepts request before Cerebras
3. **Cerebras receives clean request** - No 422 error!

The proxy sits between the router and Cerebras, giving us full control over the final request.

---

## Maintenance

**If router updates:**
- Check if `disabledTransformers` config option works in newer versions
- If so, can remove proxy and use config-based solution
- Monitor: https://github.com/musistudio/claude-code-router/issues/503

**If proxy fails:**
- Check logs: `tail /tmp/cerebras-proxy.log`
- Verify proxy running: `ps aux | grep cerebras-proxy`
- Restart: `pkill -f cerebras-proxy && ~/start-claude-isolated.sh`

---

## Alternative Solutions (Not Implemented)

1. **Patch Router Source** - Modify compiled router code (fragile, breaks on updates)
2. **Use Z.ai Provider** - Supports reasoning natively (requires separate VM setup)
3. **Wait for Router Fix** - GitHub issue filed, timeline unknown

**Current solution (proxy) is the most maintainable approach.**

---

**Status:** ✅ WORKING as of 2026-01-08
**Router Version:** v2.0.0
**Cerebras API:** OpenAI-compatible format
