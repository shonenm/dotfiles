// Search prompts in the active conversation without navigating or forking the session.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Input, SelectList, Text, fuzzyFilter } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
  pi.registerShortcut("ctrl+r", {
    description: "Search prompt history",
    handler: async (ctx) => {
      if (ctx.mode !== "tui") return;
      const prompts = ctx.sessionManager.getBranch().flatMap((entry) => {
        if (entry.type !== "message" || entry.message.role !== "user") return [];
        const content = entry.message.content;
        const text = typeof content === "string" ? content : content
          .filter((part) => part.type === "text").map((part) => part.text).join("\n");
        return text.trim() ? [text] : [];
      });
      const items = [...new Set(prompts.reverse())].map((value) => ({
        value,
        label: value.replace(/\s+/g, " ").trim(),
      }));
      if (!items.length) {
        ctx.ui.notify("No prompt history in this conversation yet.", "info");
        return;
      }

      const selected = await ctx.ui.custom<string | undefined>((tui, theme, keybindings, done) => {
        const input = new Input();
        const title = new Text(theme.fg("accent", "Search prompt history"), 0, 0);
        const help = new Text(theme.fg("dim", "Type to search · ↑↓ select · Enter restore · Esc cancel"), 0, 0);
        const listTheme = {
          selectedPrefix: (text: string) => theme.fg("accent", text),
          selectedText: (text: string) => theme.fg("accent", text),
          description: (text: string) => theme.fg("muted", text),
          scrollInfo: (text: string) => theme.fg("dim", text),
          noMatch: () => theme.fg("muted", "No matching prompts"),
        };
        let list = new SelectList(items, 8, listTheme);
        return {
          get focused() { return input.focused; },
          set focused(value: boolean) { input.focused = value; },
          render: (width) => [
            ...title.render(width), ...input.render(width), ...list.render(width), ...help.render(width),
          ],
          invalidate() { title.invalidate(); input.invalidate(); list.invalidate(); help.invalidate(); },
          handleInput(data) {
            if (keybindings.matches(data, "tui.select.cancel")) done(undefined);
            else if (keybindings.matches(data, "tui.select.confirm")) {
              const item = list.getSelectedItem();
              if (item) done(item.value);
            } else if (keybindings.matches(data, "tui.select.up") || keybindings.matches(data, "tui.select.down")) {
              list.handleInput(data);
            } else {
              input.handleInput(data);
              list = new SelectList(fuzzyFilter(items, input.getValue(), (item) => item.label), 8, listTheme);
            }
            tui.requestRender();
          },
        };
      });
      if (selected !== undefined) ctx.ui.setEditorText(selected);
    },
  });
}
