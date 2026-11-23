-- rex.py から rex do で呼ぶ。local と rex hosts の server へ 1 回の接続で問い合わせる。
local function servers()
  local list = { { label = nil, api = rex } }
  for _, label in ipairs(rex.servers()) do
    table.insert(list, { label = label, api = rex.server(label) })
  end
  return list
end

rex.action{
  name = "sessions",
  title = "Sessions on Every Host",
  run = function()
    -- 同じ host が別 label で登録されていても session ID で 1 つにする。
    local seen, result = {}, {}
    for _, server in ipairs(servers()) do
      local ok, list = pcall(server.api.call, "session.list", {})
      for _, s in ipairs(ok and list and list.sessions or {}) do
        if not seen[s.session_id] then
          seen[s.session_id] = true
          table.insert(result, { host = server.label, session_id = s.session_id, label = s.label })
        end
      end
    end
    return result
  end,
}

-- session を開き、layout 順で最初に program status を報告した pane へ focus する。
rex.action{
  name = "agent_session",
  title = "Go to First Agent Pane",
  args = { session = "string", host = "string?" },
  run = function(_, args)
    local server = args.host and rex.server(args.host) or rex
    -- host への接続は session に attach しないと session の操作を受け付けない。
    if args.host then assert(server.call("session.attach", { session_id = args.session })) end
    local view = assert(server.call("session.view", { session_id = args.session }))
    local target
    for _, window in ipairs(view.windows) do
      local layer = window.layers and window.layers[1]
      for _, block in ipairs(layer and layer.blocks or {}) do
        local status = server.call("com.superlogical.terminal.program_status", { session_id = args.session, block_id = block.block_id, args = {} })
        if status and status.records and #status.records > 0 then
          target = { window_id = window.window_id, block_id = block.block_id }
          break
        end
      end
      if target then break end
    end
    local select = { session_id = args.session }
    if target then
      assert(server.call("session.focus_block", { session_id = args.session, block_id = target.block_id }))
      select.window_id = target.window_id
    end
    local clients = assert(server.call("client.list", {}))
    for _, client in ipairs(clients.clients) do
      if client.info and client.info.kind == "app" then
        assert(server.call("client.perform", { client_id = client.client_id, action = "session.select", args = select }))
        return target or {}
      end
    end
    error("Rex app が " .. (args.host or "local") .. " に接続していません", 0)
  end,
}
