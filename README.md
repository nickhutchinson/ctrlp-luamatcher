# ctrlp-luamatcher

Matcher plug-in for CtrlP implemented using LuaJIT. Your Vim will need to have
been compiled with LuaJIT support (standard Lua will not work; this plugin
requires LuaJIT's `ffi` module).

This is more of a means for me to learn Lua, really, but I do find this useful
day to day. Perhaps you will too.


## Installation
If you use Vundle:
```vim
Plugin 'nickhutchinson/ctrlp-luamatcher'
```

Then,  add the following to your .vimrc:

```vim
let g:ctrlp_match_func  = {'match' : 'ctrlp_luamatcher#Match'}
```
