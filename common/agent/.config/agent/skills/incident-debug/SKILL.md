---
name: incident-debug
description: Investigate production incidents, errors, or unexpected behavior. Use when logs, metrics, or user reports indicate something is broken.
---

# Incident Debug

Use this skill when investigating production incidents, errors, or unexpected behavior.

## Process
1. Gather evidence: logs, error messages, recent deploys, metrics.
2. Identify the first symptom and the timeline.
3. Correlate with recent changes (commits, dependency updates, infra).
4. Form hypotheses and test them (check code, reproduce locally if safe).
5. Find the minimal fix or mitigation.
6. Document findings and preventive measures.

## Safety
- Do not run destructive queries against production databases.
- Do not expose sensitive data in outputs.
- If a rollback is safer than a fix, recommend rollback first.
