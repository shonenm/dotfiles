-- 対応が必要な pane へ全 session を横断して移動する。blocked → error → done の順、同順位は古い順。
-- 出典: grindlemire の next_ready.lua (Rex Beta Discord "Hot key to go to the next tab with a notification")。
-- program_status (OSC 7501) を読むため、Claude Code など状態を報告する program に効く。
-- done / error は、client がその pane の size を状態更新後に要求していれば (= 表示済み) 飛ばす。blocked は常に対象。
local RANK = { blocked = 1, error = 2, done = 3 }

local function call(s, b, m)
  return rex.call("block.method", { session_id = s, block_id = b, method = m }) or {}
end

local function panes(n, out)
  if n.block_id then out[#out + 1] = n.block_id
  elseif n.split then panes(n.split.before, out) panes(n.split.after, out) end
  return out
end

local function status(s, b)
  local root
  for _, r in ipairs(call(s, b, "program_status").records or {}) do
    if r.state == "blocked" then return r end
    if not r.id then root = r end
  end
  return root
end

local function seen(s, b, t)
  for _, d in ipairs(call(s, b, "size").desired or {}) do
    if (d.updated_at or "") > t then return true end
  end
end

local function ready()
  local out = {}
  for _, x in ipairs((rex.call("session.list", {}) or {}).sessions or {}) do
    local s = x.session_id
    local a = rex.call("session.attach", { session_id = s })
    for _, w in ipairs(a and a.view.windows or {}) do
      for _, l in ipairs(w.layers or {}) do
        for _, b in ipairs(panes(l.layout, {})) do
          local r = status(s, b)
          local p, t = r and RANK[r.state], r and r.updated_at or ""
          if p and (p == 1 or not seen(s, b, t)) then
            out[#out + 1] = { s = s, w = w.window_id, b = b, p = p, t = t }
          end
        end
      end
    end
  end
  table.sort(out, function(x, y) return x.p < y.p or (x.p == y.p and x.t < y.t) end)
  return out
end

rex.action{
  name = "next_ready_pane",
  title = "Next Pane That Needs You",
  category = "Dotfiles",
  run = function(ctx)
    local list = ready()
    local go = list[1]
    for i, x in ipairs(list) do
      if x.b == ctx.block_id then go = list[i % #list + 1] break end
    end
    if not go or go.b == ctx.block_id then return end
    if rex.call("session.focus_block", { session_id = go.s, block_id = go.b }) then
      rex.client.queue("session.select", { session_id = go.s, window_id = go.w })
    end
  end,
}

rex.bind("cmd+u", "next_ready_pane")
