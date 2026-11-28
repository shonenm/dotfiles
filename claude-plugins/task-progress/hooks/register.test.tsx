import { expect, test } from 'claude-code/testing'

const BAND = { plugin: 'task-progress', component: 'AbovePrompt', props: { hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 20, bodyColumns: 80, scroll: { offset: 0, bodyRows: 20 }, view: {} } } as const

test('タスクがないまま3回目の編集は1回だけ止める', async ($, on) => {
  on('tool.call', () => ({ result: {} }))
  const edit = () => $.tool.call({ tool: 'Write', file_path: '/a', content: '' })
  expect((await edit()).deny).toBeUndefined()
  expect((await edit()).deny).toBeUndefined()
  const third = await edit()
  expect(third.deny ?? third.text).toMatch(/task-progress/)
  expect((await edit()).deny).toBeUndefined()
})

test('システムプロンプトに分解の指示を足す', async ($, on) => {
  on('prompt.compose', () => ({ sections: [] }))
  const r = await $.prompt.compose({ model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] })
  expect(r.sections.map(s => s.id)).toContain('task-progress:guide')
})

test('タスクの作成・更新がバーと一覧に出て、未更新の作業 turn は差し戻される', async ($, on) => {
  on('command.register', () => ({ value: { command: 'task-list' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('classic.Stop', () => ({}))
  let n = 0
  on('tool.call', (_, e) => {
    if (e.tool === 'TaskList') return { result: { tasks: [] } }
    if (e.tool === 'TaskCreate') return { result: { task: { id: String(++n), subject: e.subject } } }
    if (e.tool === 'TaskUpdate') return { result: { success: true, taskId: e.taskId, updatedFields: ['status'] } }
    return { result: {} }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.tool.call({ tool: 'TaskCreate', subject: 'PR1', description: '' })
  await $.tool.call({ tool: 'TaskCreate', subject: 'PR2', description: '' })
  await $.tool.call({ tool: 'TaskUpdate', taskId: '1', status: 'completed' })
  await $.tool.call({ tool: 'TaskUpdate', taskId: '2', status: 'in_progress' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /1\/2/ }))?.text).toMatch(/1\/2 {2}▸ PR2/)
    // 1/2 完了なので 1/3 以上 2/3 未満の色
    expect((await ui.find({ type: 'Text', text: /^█+$/ }))?.props.color).toBe('yellow')
    expect(await ui.find({ type: 'Text', text: /\[x\] PR1/ })).toBeUndefined()
    await ui.unmount()
  }

  // バーのボタン (Ctrl+T) で開く
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'toggle' })
  expect((await ui.find({ type: 'Text', text: /\[x\] PR1/ }))?.text).toBe('[x] PR1')
  expect((await ui.find({ type: 'Text', text: /\[>\] PR2/ }))?.text).toBe('[>] PR2')
  await ui.unmount()

  // 調査だけの turn は止めない
  await $.prompt.submit({ text: 'go' } as never)
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  expect((await $.classic.Stop({ stop_hook_active: false } as never)).block).toBeUndefined()

  // タスクを更新せずに編集して終わろうとすると止める
  await $.prompt.submit({ text: 'go' } as never)
  await $.tool.call({ tool: 'Edit', file_path: '/a', old_string: 'a', new_string: 'b' })
  const stop = await $.classic.Stop({ stop_hook_active: false } as never)
  expect(stop.block).toMatch(/task-progress/)
})
