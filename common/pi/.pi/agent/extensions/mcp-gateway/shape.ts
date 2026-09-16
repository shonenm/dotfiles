import {
  prepareWoodpeckerParams,
  shapeLogsTail,
  shapePipelineList,
  shapePipelineSummary,
} from "./shapes/woodpecker.ts";

export interface ShapeResult {
  text: string;
  omitted: boolean;
  shape: string;
}

type Shaper = (text: string, params: Record<string, unknown>, shape: string) => string;
type ParamPrep = (params: Record<string, unknown>) => Record<string, unknown>;

function toolKey(server: string, tool: string): string {
  return `${server}/${tool}`;
}

const defaultShapes: Record<string, string> = {
  "woodpecker-ci/get_pipeline_status": "summary",
  "woodpecker-ci/get_logs": "tail",
  "woodpecker-ci/list_pipelines": "summary",
};

const shapers: Record<string, Shaper> = {
  "woodpecker-ci/get_pipeline_status": (text, _params, shape) =>
    shape === "summary" ? shapePipelineSummary(text) : text,
  "woodpecker-ci/list_pipelines": (text, _params, shape) =>
    shape === "summary" ? shapePipelineList(text) : text,
  "woodpecker-ci/get_logs": (text, params, shape) => {
    if (shape !== "tail") return text;
    const lines = typeof params.lines === "number" && params.lines > 0 ? params.lines : 80;
    return shapeLogsTail(text, lines);
  },
};

const paramPreps: Record<string, ParamPrep> = {
  "woodpecker-ci/get_logs": (params) => prepareWoodpeckerParams("get_logs", params),
};

export function shapeResult(input: {
  server: string;
  tool: string;
  text: string;
  params: Record<string, unknown>;
  shape?: string;
}): ShapeResult {
  const key = toolKey(input.server, input.tool);
  const selected = input.shape ?? defaultShapes[key];
  if (input.params.detail === "full" || selected === "full") {
    return { text: input.text, omitted: false, shape: "full" };
  }

  const shaper = selected === undefined ? undefined : shapers[key];
  if (!shaper || selected === undefined) {
    return { text: input.text, omitted: false, shape: "identity" };
  }

  try {
    const next = shaper(input.text, input.params, selected);
    return { text: next, omitted: next !== input.text, shape: selected };
  } catch {
    return { text: input.text, omitted: false, shape: selected };
  }
}

export function prepareToolParams(
  server: string,
  tool: string,
  params: Record<string, unknown>,
  shape?: string,
): Record<string, unknown> {
  const result = { ...params };
  const skipPrep = result.detail === "full" || shape === "full";
  delete result.detail;
  if (skipPrep) return result;
  const prep = paramPreps[toolKey(server, tool)];
  return prep ? prep(result) : result;
}
