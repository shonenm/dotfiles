import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export interface CursorHostSkill {
  name: string;
  description: string;
  filePath?: string;
  location?: string;
}

export interface CursorHostContextFile {
  path: string;
  content: string;
}

export interface CursorHostPromptInput {
  cwd?: string;
  date?: string;
  appendSystemPrompt?: string;
  customPrompt?: string;
  contextFiles?: CursorHostContextFile[];
  skills?: CursorHostSkill[];
}

const HOST_INSTRUCTIONS = "# Host Instructions";
const PROJECT_CONTEXT = "# Project Context";

export function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export function buildCursorHostPrompt(input: CursorHostPromptInput): string {
  const sections: string[] = [];
  const host = [input.customPrompt?.trim(), input.appendSystemPrompt?.trim()]
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
        skills: options.skills,
      }),
    };
  });

  pi.on("session_before_compact", (event, ctx) => {
    if (!isCursorAgent(ctx)) return;
    if (event.reason === "manual") return;
    return { cancel: true };
  });
}
