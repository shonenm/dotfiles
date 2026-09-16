export function prepareWoodpeckerParams(tool: string, params: Record<string, unknown>): Record<string, unknown> {
  const result = { ...params };
  if (tool === "get_logs" && (typeof result.lines !== "number" || result.lines <= 0)) {
    result.lines = 80;
    result.tail = true;
  }
  return result;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : undefined;
}

function shortCommit(value: unknown): unknown {
  if (typeof value !== "string") return value;
  return value.length > 12 ? `${value.slice(0, 12)}…` : value;
}

function failedState(value: unknown): boolean {
  return typeof value === "string" && /fail|kill|error/i.test(value);
}

export function shapePipelineSummary(text: string): string {
  const parsed: unknown = JSON.parse(text);
  const source = record(parsed) ?? {};
  const workflows = Array.isArray(source.workflows) ? source.workflows : [];
  return JSON.stringify({
    number: source.number,
    status: source.status,
    commit: shortCommit(source.commit),
    event: source.event,
    ref: source.ref,
    workflows: workflows.map((workflow) => {
      const item = record(workflow) ?? {};
      const children = Array.isArray(item.children)
        ? item.children
        : Array.isArray(item.steps)
          ? item.steps
          : [];
      const failedSteps = children
        .filter((child) => {
          const step = record(child) ?? {};
          return failedState(step.state) || failedState(step.status) || (step.exit_code !== undefined && step.exit_code !== 0);
        })
        .map((child) => {
          const step = record(child) ?? {};
          return {
            id: step.id,
            name: step.name,
            exit_code: step.exit_code,
          };
        });
      return {
        name: item.name,
        state: item.state ?? item.status,
        ...(failedSteps.length > 0 ? { failed_steps: failedSteps } : {}),
      };
    }),
  });
}

function collapseMessage(value: unknown): unknown {
  if (typeof value !== "string") return value;
  return value.split(/\r?\n/, 1)[0];
}

export function shapePipelineList(text: string): string {
  const parsed: unknown = JSON.parse(text);
  const collapse = (item: unknown): unknown => {
    const source = record(item);
    if (!source) return item;
    const result = { ...source };
    if ("message" in result) result.message = collapseMessage(result.message);
    if (record(result.commit)?.message !== undefined) {
      result.commit = { ...record(result.commit), message: collapseMessage(record(result.commit)?.message) };
    }
    return result;
  };
  if (Array.isArray(parsed)) return JSON.stringify(parsed.map(collapse));
  const source = record(parsed);
  if (!source) return text;
  const result = { ...source };
  for (const key of ["pipelines", "list"]) {
    if (Array.isArray(result[key])) result[key] = result[key].map(collapse);
  }
  return JSON.stringify(result);
}

export function shapeLogsTail(text: string, lines: number): string {
  const parsed: unknown = JSON.parse(text);
  if (Array.isArray(parsed)) return JSON.stringify({ logs: parsed.slice(-lines), _mcp: { shape: "tail", omitted: "older log entries", kept: lines } });
  const source = record(parsed);
  if (!source || !Array.isArray(source.logs)) return text;
  return JSON.stringify({
    ...source,
    logs: source.logs.slice(-lines),
    _mcp: { shape: "tail", omitted: "older log entries", kept: lines },
  });
}
