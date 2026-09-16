import { homedir } from "node:os";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RESERVED = [
  "btw",
  "compact",
  "login",
  "mcp",
  "model",
  "models",
  "session-export",
  "session-import",
  "session-name",
  "sessions",
  "skill",
  "stash",
  "stash-clear",
  "status",
  "statusline",
];

const SKILL_DIRS = [
  join(homedir(), ".config/agent/skills"),
  join(homedir(), ".pi/agent/skills"),
];

export function parseSkillFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  const fm = match?.[1] ?? "";
  const name = fm.match(/^name:\s*(.+)$/m)?.[1]?.trim();
  const rawDescription = fm.match(/^description:\s*(.+)$/m)?.[1]?.trim() ?? "";
  const description = rawDescription.replace(/^["']|["']$/g, "");
  return {
    name,
    description,
    slashOnly: /^disable-model-invocation:\s*true$/m.test(fm),
  };
}

export function discoverSlashSkills(dirs = SKILL_DIRS) {
  const found = new Map();
  for (const dir of dirs) {
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const filePath = join(dir, entry.name, "SKILL.md");
      if (!entry.isDirectory() || !existsSync(filePath)) continue;
      const parsed = parseSkillFrontmatter(readFileSync(filePath, "utf8"));
      const name = parsed.name || entry.name;
      if (RESERVED.includes(name) || name.startsWith("d-") || found.has(name)) continue;
      found.set(name, {
        name,
        description: parsed.description,
        filePath,
        slashOnly: parsed.slashOnly,
      });
    }
  }
  return [...found.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export default function skillSlashExtension(pi: ExtensionAPI) {
  const skills = discoverSlashSkills();

  pi.registerCommand("skills", {
    description: "List skills and how to invoke them",
    handler: async (_args, ctx) => {
      const lines = skills.map((skill) => {
        const mode = skill.slashOnly ? "slash-only" : "auto";
        return `/${skill.name}  (${mode})  ${skill.description}`;
      });
      ctx.ui.notify(
        lines.length > 0
          ? `Skills - /name or /skill:name\n${lines.join("\n")}`
          : "No skills found",
        "info",
      );
    },
  });

  for (const skill of skills) {
    pi.registerCommand(skill.name, {
      description: skill.slashOnly
        ? `${skill.description} (slash-only)`
        : skill.description,
      handler: async (args, ctx) => {
        const suffix = args?.trim() ? ` ${args.trim()}` : "";
        await ctx.sendUserMessage(`/skill:${skill.name}${suffix}`, {
          expandPromptTemplates: true,
        });
      },
    });
  }
}
