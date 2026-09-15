#!/usr/bin/env python3
"""Offline protocol fixture. Never reads account files or contacts a provider."""
import json
import os
import sys
import time

is_grok = "agent" in sys.argv
mode = os.path.basename(os.environ["GROK_HOME" if is_grok else "CODEX_HOME"])
initialized = False
for line in sys.stdin:
    request = json.loads(line)
    if is_grok:
        assert request.get("jsonrpc") == "2.0"
        assert "XAI_API_KEY" not in os.environ
        assert "--no-leader" in sys.argv
    else:
        assert "OPENAI_API_KEY" not in os.environ
    method = request.get("method")
    if mode == "timeout":
        time.sleep(10)
    if mode == "exit":
        sys.exit(0)
    if mode == "error":
        print(json.dumps({"id": request["id"], "error": {"message": "SECRET_TOKEN"}}), flush=True)
        continue
    if method == "initialized":
        initialized = True
        continue
    if method == "initialize":
        result = {"userAgent": "fixture"}
    elif method == "account/read":
        assert initialized
        result = {"account": {"type": "chatgpt", "email": "fixture@example.com", "planType": "plus"}}
    elif method == "account/rateLimits/read":
        result = {"rateLimits": {"primary": {"usedPercent": 42, "windowDurationMins": 300}}}
    elif method == "_x.ai/auth/check_subscription":
        result = {"authenticated": True, "meta": {"subscription_tier": "SuperGrok"}}
    elif method == "_x.ai/billing":
        result = {"config": {"creditUsagePercent": 37}}
    else:
        continue
    print(json.dumps({"method": "account/updated", "params": {}}), flush=True)
    response = json.dumps({"id": request["id"], "result": result}) + "\n"
    for start in range(0, len(response), 11):
        sys.stdout.write(response[start:start + 11])
        sys.stdout.flush()
