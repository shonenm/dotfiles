// Highlight names of Pi's currently loaded skills in the prompt editor.
// Wrap the existing editor factory so package-provided editors (e.g. workflows)
// retain their input behavior and rendering.

import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

type AnsiToken = { escape?: string; character?: string };
type HighlightState = { names: string[] };
type EditorFactory = NonNullable<ReturnType<ExtensionContext["ui"]["getEditorComponent"]>>;
type MarkedFactory = EditorFactory & { __piSkillHighlightState?: HighlightState };

const factoryMarker = "__piSkillHighlightState" as const;

function decodeXml(value: string): string {
  return value.replace(/&(amp|lt|gt|quot|apos);/g, (_match, entity: string) => ({
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
  })[entity]!);
}

export function skillNamesFromPrompt(prompt: string): string[] {
  const section = prompt.match(/<available_skills>([\s\S]*?)<\/available_skills>/)?.[1] ?? "";
  return [...section.matchAll(/<name>([\s\S]*?)<\/name>/g)]
    .map((match) => decodeXml(match[1]!).trim())
    .filter(Boolean);
}

function tokenizeAnsi(line: string): AnsiToken[] {
  const tokens: AnsiToken[] = [];
  for (let index = 0; index < line.length;) {
    if (line[index] !== "\x1b") {
      tokens.push({ character: line[index++]! });
      continue;
    }

    let end = index + 1;
    if (line[end] === "[") {
      while (++end < line.length && !(line[end]! >= "@" && line[end]! <= "~")) {}
      end++;
    } else if (["]", "_", "P", "^"].includes(line[end] ?? "")) {
      while (++end < line.length && line[end] !== "\x07" && !(line[end] === "\x1b" && line[end + 1] === "\\")) {}
      end += line[end] === "\x1b" ? 2 : 1;
    } else {
      end++;
    }
    tokens.push({ escape: line.slice(index, end) });
    index = end;
  }
  return tokens;
}

function skillRanges(text: string, names: string[]): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
  for (const name of names) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pattern = new RegExp(`(?<![A-Za-z0-9_-])${escaped}(?![A-Za-z0-9_-])`, "gi");
    for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
      ranges.push([match.index, match.index + match[0].length]);
    }
  }
  return ranges;
}

export function highlightSkills(line: string, names: string[], accent: (text: string) => string): string {
  if (names.length === 0) return line;

  const tokens = tokenizeAnsi(line);
  const ranges = skillRanges(tokens.flatMap((token) => token.character ?? []).join(""), names);
  if (ranges.length === 0) return line;

  let visibleIndex = 0;
  return tokens.map((token) => {
    if (token.escape !== undefined) return token.escape;
    const highlighted = ranges.some(([start, end]) => visibleIndex >= start && visibleIndex < end);
    visibleIndex++;
    return highlighted ? accent(token.character!) : token.character!;
  }).join("");
}

export default function (pi: ExtensionAPI) {
  let state: HighlightState = { names: [] };

  const updateNames = (names: Iterable<string>) => {
    state.names = [...new Set([...names].filter(Boolean))].sort((a, b) => b.length - a.length);
  };

  pi.on("resources_discover", (_event, ctx) => {
    const names = skillNamesFromPrompt(ctx.getSystemPrompt());
    const existing = ctx.ui.getEditorComponent() as MarkedFactory | undefined;
    if (existing?.[factoryMarker]) {
      state = existing[factoryMarker]!;
      updateNames(names);
      return;
    }
    updateNames(names);

    const factory: MarkedFactory = (tui, theme, keybindings) => {
      const editor = existing ? existing(tui, theme, keybindings) : new CustomEditor(tui, theme, keybindings);
      const render = editor.render.bind(editor);
      editor.render = (width) => render(width).map((line) => highlightSkills(line, state.names, (text) => ctx.ui.theme.fg("accent", text)));
      return editor;
    };
    factory[factoryMarker] = state;
    ctx.ui.setEditorComponent(factory);
  });

  pi.on("before_agent_start", (event) => {
    updateNames(event.systemPromptOptions.skills?.map((skill) => skill.name) ?? []);
  });
}
