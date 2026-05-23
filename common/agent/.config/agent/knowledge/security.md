# Security

- Never send secrets to external tools — this includes `.env` files, API keys, private keys, tokens, customer data, internal URLs, auth cookies, and private source code.
- Three-tier permission:
  - **allow**: Public package names, public error messages, public docs queries.
  - **ask**: Stack traces, file paths, repository-specific questions.
  - **deny**: Secrets, credentials, private source full text.
- Summarize private errors before searching — remove file paths, credentials, and internal context.
- Ask before destructive commands — block `rm -rf`, `sudo`, `DROP`, `DELETE FROM`.
- Do not read `.env*`, private keys, credentials, or production dumps.
