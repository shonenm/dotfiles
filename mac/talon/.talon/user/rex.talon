app.bundle: com.superlogical.rex
and tag: user.rex_commands
and not tag: user.aqua_recording
-
# Conformer は発話を文法のどれかに当てはめるため、個別のコマンドにすると近い名前へ寄せられる。
# 発話は全部ここで受け、rex.py がコマンド名や tab 名と完全に一致したときだけ動かす。
<phrase>: user.rex_phrase("{phrase}")
