-- Talon の rex.py から呼ぶ、tab 名での移動。
local function servers()
  local list = { { label = nil, api = rex } }
  for _, label in ipairs(rex.servers()) do
    table.insert(list, { label = label, api = rex.server(label) })
  end
  return list
end

-- rex do で script として実行し、rex hosts の各 host へ 1 回の接続で問い合わせる。
rex.action{
  name = "dotfiles_voice_tabs",
  title = "Voice: Tabs on Every Host",
  category = "Dotfiles",
  run = function()
    -- 同じ host が別 label で登録されていても session ID で 1 つにする。
    local seen, result = {}, {}
    for _, server in ipairs(servers()) do
      local ok, list = pcall(server.api.call, "session.list", {})
      for _, s in ipairs(ok and list and list.sessions or {}) do
        if not seen[s.session_id] then
          seen[s.session_id] = true
          -- rex do の接続は local でも session に attach しないと session の操作を受け付けない。
          server.api.call("session.attach", { session_id = s.session_id })
          local view = server.api.call("session.view", { session_id = s.session_id })
          for _, window in ipairs(view and view.windows or {}) do
            table.insert(result, { host = server.label, session_id = s.session_id, session = s.label,
              window_id = window.window_id, label = window.label })
          end
        end
      end
    end
    return result
  end,
}

-- rex do から呼ぶ action は remote host への接続を持たない。Rex app の key 入力から呼ぶ action だけが
-- app の繋いでいる host を使えるため、remote の tab は行き先を先に預け、key で dotfiles_voice_go を起動する。
local pending
rex.action{
  name = "dotfiles_voice_target",
  title = "Voice: Set Tab Target",
  category = "Dotfiles",
  args = { session = "string", window = "string", host = "string?", next = "string?" },
  run = function(_, args) pending = args end,
}

-- tab を開き、layout 順で最初に program status を報告した pane（agent）へ focus する。
-- next を付けると、focus 中の agent の次へ順に移る。agent がなければ tab を開くだけ。
-- local の tab は rex do から session と window を渡して呼ぶ。key から起動すると rex が
-- app の表示中の session の server を指し、local の server に届かないため。
rex.action{
  name = "dotfiles_voice_go",
  title = "Voice: Go to Tab Agent",
  category = "Dotfiles",
  args = { session = "string?", window = "string?", next = "string?" },
  run = function(_, given)
    local args = given.session and given or assert(pending, "行き先がありません")
    pending = nil
    local server, view = rex, nil
    if args.host then
      -- 同じ host が rex hosts に別 label（aether と matsushima@aether）で登録されていると、app の繋いでいる label が
      -- 一覧を取った label と違うことがあるため、app の繋いでいる host から session を持つものを探す。
      for _, label in ipairs(rex.servers()) do
        local attached = rex.server(label).call("session.attach", { session_id = args.session })
        if attached then server, view = rex.server(label), attached.view break end
      end
    else
      view = (server.call("session.attach", { session_id = args.session }) or {}).view
    end
    if not view then error("session " .. args.session .. " を持つ host に Rex app が接続していません", 0) end
    local agents, current = {}, nil
    for _, window in ipairs(view.windows) do
      if window.window_id == args.window then
        local layer = window.layers and window.layers[1]
        for _, block in ipairs(layer and layer.blocks or {}) do
          local status = server.call("com.superlogical.terminal.program_status", { session_id = args.session, block_id = block.block_id, args = {} })
          if status and status.records and #status.records > 0 then
            table.insert(agents, block.block_id)
            if block.block_id == window.focused_block_id then current = #agents end
          end
        end
      end
    end
    local target = agents[args.next and current and current % #agents + 1 or 1]
    if target then
      assert(server.call("session.focus_block", { session_id = args.session, block_id = target }))
    end
    local clients = assert(server.call("client.list", {}))
    for _, client in ipairs(clients.clients) do
      if client.info and client.info.kind == "app" then
        assert(server.call("client.perform", { client_id = client.client_id, action = "session.select",
          args = { session_id = args.session, window_id = args.window } }))
        return { block_id = target }
      end
    end
    error("Rex app が " .. (args.host or "local") .. " に接続していません", 0)
  end,
}
rex.bind("cmd+ctrl+alt+shift+v", "dotfiles_voice_go")
