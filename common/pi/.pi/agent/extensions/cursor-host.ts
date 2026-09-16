import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export interface CursorHostContextFile {
  path: string;
  content: string;
}

export const CURSOR_HOST_SKILL_POLICY = [
  "Skills are not listed in this prompt. The user invokes them with /name or /skill:name;",
  "Pi then expands that SKILL.md into the user turn.",
  "Do not browse ~/.cursor/skills, ~/.claude/skills, ~/.config/agent/skills,",
  ".cursor/skills, .agents/skills, or other SKILL.md catalogs unless that skill was expanded this turn.",
].join(" ");

export interface CursorHostPromptInput {
  cwd?: string;
  date?: string;
  appendSystemPrompt?: string;
  customPrompt?: string;
  contextFiles?: CursorHostContextFile[];
}

const HOST_INSTRUCTIONS = "# Host Instructions";
const PROJECT_CONTEXT = "# Project Context";

export function buildCursorHostPrompt(input: CursorHostPromptInput): string {
  const sections: string[] = [];
  const host = [CURSOR_HOST_SKILL_POLICY, input.customPrompt?.trim(), input.appendSystemPrompt?.trim()]
    .filter(Boolean)
    .join("\n\n");
  if (host) sections.push(`${HOST_INSTRUCTIONS}\n${host}`);

  if (input.contextFiles?.length) {
    const files = input.contextFiles
      .filter((file) => file.path && file.content.trim())
      .map((file) => `## ${file.path}\n${file.content.trim()}`)
      .join("\n\n");
    if (files) sections.push(`${PROJECT_CONTEXT}\n\n${files}`);
  }

  sections.push(`Current date: ${input.date ?? new Date().toISOString().slice(0, 10)}`);
  if (input.cwd) sections.push(`Current working directory: ${input.cwd}`);
  return sections.join("\n\n");
}

function isCursorAgent(ctx: ExtensionContext): boolean {
  return ctx.model?.provider === "cursor-agent";
}

export default function cursorHostExtension(pi: ExtensionAPI): void {
  pi.on("before_agent_start", (event, ctx) => {
    if (!isCursorAgent(ctx)) return;
    const options = event.systemPromptOptions;
    return {
      systemPrompt: buildCursorHostPrompt({
        cwd: options.cwd || ctx.cwd,
        appendSystemPrompt: options.appendSystemPrompt,
        customPrompt: options.customPrompt,
        contextFiles: options.contextFiles,
      }),
    };
  });

  pi.on("session_before_compact", (event, ctx) => {
    if (!isCursorAgent(ctx)) return;
    if (event.reason === "manual") return;
    return { cancel: true };
  });
}
