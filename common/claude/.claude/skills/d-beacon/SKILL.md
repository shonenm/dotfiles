---
name: d-beacon
description: 現在の環境をaerospaceワークスペースに紐づけます。通知バッジを正しいワークスペースに表示するために使用します。
user-invocable: true
argument-hint: "<workspace番号>"
allowed-tools: Bash
disable-model-invocation: true
---

```!bash
beacon ${1}
```
