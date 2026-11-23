-
settings():
    # 言い終わりを待つ時間。既定は 0.3 秒。
    speech.timeout = 0.2
    # 標準の字幕は大きく画面下に出るため、rex.py が実行したコマンドだけを画面中央に小さく出す。
    speech._subtitles = false
