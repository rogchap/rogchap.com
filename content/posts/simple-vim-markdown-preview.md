---
title: "Simple Vim Markdown Preview"
date: 2020-01-09T21:46:34+11:00
type: post
tags:
- Vim
---

There are a lot of Vim plugins that allow you to preview markdown files:

* [iamcco/markdown-preview.vim](https://github.com/iamcco/markdown-preview.vim)
* [JamshedVesuna/vim-markdown-preview](https://github.com/JamshedVesuna/vim-markdown-preview)
* [MikeCoder/markdown-preview.vim](https://github.com/MikeCoder/markdown-preview.vim)
* [pingao777/markdown-preview-sync](https://github.com/pingao777/markdown-preview-sync)
* [suan/vim-instant-markdown](https://github.com/suan/vim-instant-markdown)
* [PratikBhusal/vim-grip](https://github.com/PratikBhusal/vim-grip)
* [mgor/vim-markdown-grip](https://github.com/mgor/vim-markdown-grip)

But to name a few.

I was looking for something simple; but most of these plugins had options and setting, commands and auto commands that
was just too bloated for my needs.

Most of these tools use a separate tool to render the markdown to the browser; [grip](https://github.com/joeyespo/grip)
is a cli application that renders markdown via the GitHub API, and is simple to install:

```zsh
$ brew install grip
```

I would prefer to render offline, but grip does what I need for now. 

## No plugin required

With `grip` installed I can simple run it with:

```vim
:! grip %
```
or in a Vim terminal:
```vim
:term grip %
```

## Homemade plugin

The above commands are great, but I wanted something more integrated into Vim. Using this [Reddit
post](https://www.reddit.com/r/vim/comments/8asgjj/topnotch_vim_markdown_live_previews_with_no/) as inspiration, I
adapted the code to work in Vim8:

```vimscript
" .vim/plugin/local.vim
command! MarkdownPreview call local#mdpreview#start()
command! MarkdownStopPreview call local#mdpreview#stop()
```

```vimscript
" .vim/autoload/local/mdpreview.vim
func! local#mdpreview#start() abort
    call local#mdpreview#stop()
    let s:mdpreview_job_id = job_start(
        \ "/bin/zsh -c \"grip -b ". shellescape(expand('%:p')) . " 0 2>&1 | awk '/Running/ { print \\$4 }'\"",
        \ { 'out_cb': 'OnGripStart', 'pty': 1 })
    func! OnGripStart(_, output)
        echo "grip " . a:output
    endfunc
endfunc

func! local#mdpreview#stop() abort
    if exists('s:mdpreview_job_id')
        call job_stop(s:mdpreview_job_id)
        unlet s:mdpreview_job_id
    endif
endfunc
```
I also wanted the `grip` server to stop when I changed vim buffers so I also added this `autocmd`:
```vimscript
" .vim/plugin/local.vim
au BufLeave * call local#mdpreview#stop()
```

Simple homemade plugin for markdown preview; all I do now is call `:MarkdownPreview` and `grip` will preview my markdown
file in my default browser.
