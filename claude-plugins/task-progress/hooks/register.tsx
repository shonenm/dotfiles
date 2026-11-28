import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Status, Task } from '../types'

const tasks = atom({ plugin: 'task-progress', key: 'tasks' } as const, [], { shape: 'tasks-1' })
const isListOpen = atom({ plugin: 'task-progress', key: 'isListOpen' } as const, false)

const BAR = 20
// 進捗率でゲージの色を変える: 1/3 未満は赤、2/3 未満は黄、完了前は水色、完了で緑
const gaugeColor = (ratio: number) =>
  ratio >= 1 ? 'green' : ratio >= 2 / 3 ? 'cyan' : ratio >= 1 / 3 ? 'yellow' : 'red'
// タスクが1件もないまま編集できる回数。これを超える最初の編集を1回だけ止める
const EDITS_BEFORE_PLAN = 2
const EDIT_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit'])
const GUIDE = {
  id: 'task-progress:guide',
  scope: 'session',
  text: '複数のPR・複数のステップにまたがる作業では、着手前に TaskCreate で作業を分解する（PR 単位なら subject を「PR1: ...」の形にする）。着手時に TaskUpdate で in_progress、終わったら completed にする。進捗はプロンプト上のバーと一覧で人間に表示される。',
} as const
const MARK = { completed: '[x]', in_progress: '[>]', pending: '[ ]' } as const

// TaskList の結果が正本。表示側のずれをここで直す
const sync = ($: Parameters<typeof update>[0], result: unknown) =>
  update($, tasks, () =>
    (result as { tasks: Task[] }).tasks.map(({ id, subject, status }) => ({ id, subject, status })),
  )

export const register: Register = on => {
  // ponytail: turn 内の編集回数だけ数える。未更新判定は「Task* を1回も呼ばずに編集した turn」
  let editCalls = 0
  let taskCalls = 0
  let editsWithoutPlan = 0
  let hasRefused = false

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'task-list', description: 'タスク一覧の表示/非表示を切り替える' })
    // resume・reload 時は既存のタスク一覧を取り込む
    const ran = await $.tool.call({ tool: 'TaskList' })
    if (ran.deny === undefined && !ran.isError) await sync($, ran.result)

    return next(e)
  })

  on('command.run', { command: 'task-list' }, async $ => {
    const isOpen = await update($, isListOpen, v => !v)

    return { text: isOpen ? 'タスク一覧を表示' : 'タスク一覧を非表示' }
  }).catch(() => ({ text: 'task-progress: 切り替えに失敗' }))

  on('prompt.submit', ($, e, next) => {
    editCalls = 0
    taskCalls = 0

    return next(e)
  }).catch(($, e, next) => next(e))

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)

    return { ...r, sections: [...r.sections, GUIDE] }
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    // サブエージェントの編集は数えない
    if (EDIT_TOOLS.has(e.tool) && !(e as { agentId?: string }).agentId && !hasRefused && (await read($, tasks)).length === 0) {
      editsWithoutPlan += 1
      if (editsWithoutPlan > EDITS_BEFORE_PLAN) {
        hasRefused = true

        return { deny: 'task-progress: タスクがないまま編集が続いています。先に TaskCreate で作業を分解してから再実行してください（1ファイルの小修正なら、そのまま再実行してよい）。' }
      }
    }
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError) return ran

    if (e.tool === 'TaskCreate') {
      taskCalls += 1
      const t = (ran.result as { task: { id: string; subject: string } }).task
      await update($, tasks, list => [...list, { id: t.id, subject: t.subject, status: 'pending' as const }])
    } else if (e.tool === 'TaskUpdate') {
      taskCalls += 1
      const r = ran.result as { success: boolean }
      if (r.success) {
        await update($, tasks, list =>
          e.status === 'deleted'
            ? list.filter(t => t.id !== e.taskId)
            : list.map(t =>
                t.id === e.taskId
                  ? { ...t, subject: e.subject ?? t.subject, status: (e.status as Status | undefined) ?? t.status }
                  : t,
              ),
        )
      }
    } else if (e.tool === 'TaskList') {
      taskCalls += 1
      await sync($, ran.result)
    } else if (EDIT_TOOLS.has(e.tool)) {
      editCalls += 1
    }

    return ran
  }).catch(($, e, next) => next(e))

  // 作業中のタスクがあるのに、編集した turn で一度も更新しなかったら1回だけ差し戻す
  on('classic.Stop', async ($, e, next) => {
    const result = await next(e)
    if (e.stop_hook_active || result.block || editCalls === 0 || taskCalls > 0) return result
    const open = (await read($, tasks)).filter(t => t.status !== 'completed')
    if (!open.some(t => t.status === 'in_progress')) return result

    return {
      ...result,
      block: 'task-progress: 作業中のタスクがあるのに、この turn でタスク一覧を更新していません。TaskUpdate で状態を更新してから終了してください。',
    }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const list = await read($, tasks)
    if (e.props.hasSurvey || list.length === 0) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const done = list.filter(t => t.status === 'completed').length
    const current = list.find(t => t.status === 'in_progress')
    const filled = Math.round((done / list.length) * BAR)
    const isOpen = await read($, isListOpen)
    const room = Math.max(1, e.props.maxRows - 2)

    return (
      <Box flexDirection="column">
        <Box>
        <Text>
          <Text color={gaugeColor(done / list.length)}>{'█'.repeat(filled)}</Text>
          <Text dimColor>{'░'.repeat(BAR - filled)}</Text> {done}/{list.length}
          {current ? `  ▸ ${current.subject}` : ''}
        </Text>
        {/* ponytail: Ctrl+T (app:toggleTodos) をこのボタンに割り当て、標準の一覧の代わりにこちらを開閉する */}
        <Button
          key="toggle"
          plain
          dimColor
          action="app:toggleTodos"
          label={isOpen ? '  一覧を閉じる' : '  一覧'}
          onPress={() => update($, isListOpen, v => !v)}
        />
        </Box>
        {isOpen &&
          list.slice(0, room).map(t => (
            <Text dimColor={t.status === 'completed'} bold={t.status === 'in_progress'}>
              {MARK[t.status]} {t.subject}
            </Text>
          ))}
      </Box>
    )
  })
}
