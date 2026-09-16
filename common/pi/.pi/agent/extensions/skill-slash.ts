import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const SKILL_PREFIX = "/skill:";

export function rewriteSkillSlash(text: string, skillNames: string[], reservedNames: string[]): string {
  if (!text.startsWith("/") || text.startsWith(SKILL_PREFIX)) return text;
  const match = /^\/([A-Za-z0-9][A-Za-z0-9._-]*)(\s[\s\S]*)?$/.exec(text);
  if (!match) return text;
  const name = match[1];
  if (reservedNames.includes(name) || !skillNames.includes(name)) return text;
  return `${SKILL_PREFIX}${name}${match[2] ?? ""}`;
}

function skillNamesFromCommands(pi: ExtensionAPI): string[] {
  return pi
    .getCommands()
    .filter((command) => command.source === "skill" && command.name.startsWith("skill:"))
    .map((command) => command.name.slice("skill:".length))
    .filter(Boolean);
}

function reservedNamesFromCommands(pi: ExtensionAPI): string[] {
  return pi
    .getCommands()
    .filter((command) => command.source !== "skill")
    .map((command) => command.name);
}

export default function skillSlashExtension(pi: ExtensionAPI): void {
  pi.registerCommand("skills", {
    description: "List loaded skill names (invoke with /name)",
    handler: async (_args, ctx) => {
      const names = skillNamesFromCommands(pi);
      ctx.ui.notify(names.length ? names.map((name) => `/${name}`).join("\n") : "No skills loaded.");
    },
  });

  pi.on("input", (event, _ctx: ExtensionContext) => {
    const next = rewriteSkillSlash(event.text, skillNamesFromCommands(pi), reservedNamesFromCommands(pi));
    if (next === event.text) return;
    return { action: "transform" as const, text: next, images: event.images };
  });
}
