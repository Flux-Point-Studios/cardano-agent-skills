# Operator notes

This operator uses OpenClaw's **command-dispatch: tool** mode to route the slash command directly to the **Exec Tool** (no model).

Recommended OpenClaw session defaults:
- `/exec host=gateway security=allowlist ask=on-miss`

This helps ensure approval-gated execution (depending on your exec approvals policy) and blocks shell chaining/redirection in allowlist mode.
