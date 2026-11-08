# auto-read

- Neovim の Lua プラグイン
- 指定したファイルを `tail -f` し、追記された行を現在のバッファに追記します

ファイル全体の読み直しではなく、追記された分だけをバッファに足します。
出力先は「現在のバッファ」で、tail するファイルとは無関係です。スクラッチバッファでも構いません。

## インストール

### lazy.nvim を使用する場合

```lua
{
  "anekos/auto-read.nvim",
  cmd = { "AutoRead", "AutoReadStop" },
  config = function()
    require("auto-read").setup({
      tail_command = "tail",   -- デフォルト値
      initial_lines = nil,     -- デフォルト値
      follow_name = false,     -- デフォルト値
      follow_cursor = true,    -- デフォルト値
      reset_modified = false,  -- デフォルト値
      notify = true,           -- デフォルト値
    })
  end
}
```

## コマンド

- `:AutoRead {file}` - `{file}` を tail して、現在のバッファに追記します
  - 既定ではファイルの先頭から読み込みます
- `:AutoRead! {file}` - 既存の内容は読まず、以降の追記のみを追記します (`tail -n 0 -f` 相当)
- `:AutoReadStop` - 現在のバッファの tail を終了します

1 つのバッファで tail できるファイルは 1 つです。
バッファが unload / wipeout された時点で自動的に終了します。

## 設定項目

- `tail_command` (string, default: `tail`): 使用する `tail` コマンド
- `initial_lines` (number|nil, default: nil): 開始時に読み込む行数
  - `nil` ならファイルの先頭から全て (`tail -n +1`)
  - 数値ならその行数だけ (`tail -n {N}`)
  - `:AutoRead!` を使った場合はこの設定は無視されます
- `follow_name` (boolean, default: false): `tail -F` を使い、ログローテーションに追従します
  - ローテーション後は新しいファイルの先頭から読み込まれます
- `follow_cursor` (boolean, default: true): 追記時に末尾へ自動スクロールします
  - 追記の直前にカーソルが末尾行にあったウィンドウだけが対象です
  - 上の方を読んでいる間は引き戻されません
- `reset_modified` (boolean, default: false): 追記後に `'modified'` を下ろします
  - 保存する気のないバッファで、終了時の警告を避けたい場合に `true` にします
- `notify` (boolean, default: true): 開始・終了を `vim.notify` で知らせます
  - `false` でもエラーと警告は通知されます

## Lua API

```lua
local auto_read = require("auto-read")

auto_read.start(path, opts)  -- opts: { buf = number, lines = number, from_end = boolean }
auto_read.stop(buf)          -- buf 省略時は現在のバッファ
auto_read.is_running(buf)    -- tail 中かどうか
auto_read.tailing_path(buf)  -- tail しているファイルのパス (していなければ nil)
```

## 使い方

1. 出力先のバッファを用意します (`:enew` など)
2. `:AutoRead /var/log/foo.log` で tail を開始
3. ファイルに追記された行がバッファに流れ込みます
4. 末尾にカーソルを置いておくと自動で追従し、上へ移動すると止まります
5. `:AutoReadStop` で終了

## 備考

- 改行で終わっていない行は、改行が届くまで追記されません
- 追記によってバッファは `'modified'` になります。ファイルを開いているバッファを出力先にすると、
  保存時にそのファイルを壊すので注意してください
