#!/usr/bin/env lua5.3

_REQ = _REQ and (_REQ + 1) or 1
local FC = require 'freechains.cfg'
_REQ = _REQ - 1

local function split (str)
    local ret = {}
    for it in string.gmatch(str, "([^\t]*)") do
        table.insert(ret, it)
    end
    return ret
end

function FC.exe.zen (title, forms, cmd)
    forms = forms and '--forms --separator="\t"' or ''
    local z = (
        'zenity'                    ..
        '   '..forms                ..
        '   --title="'..title..'"'  ..
        '   '..cmd
    )
    local ret = FC.exe._(z)
    return ret and split(ret)
end

local cmd_host_create    = FC.cmd.host.create
local cmd_host_nick_add  = FC.cmd.host.nick.add
local cmd_chain_join     = FC.cmd.chain.join
local cmd_chain_post     = FC.cmd.chain.post
local cmd_chain_like     = FC.cmd.chain.like
local cmd_chain_peer_add = FC.cmd.chain.peer.add
local cmd_chain_bcast    = FC.cmd.chain.bcast

FC.cmd.host.create = function (port)
    local ret = FC.exe.zen('Welcome to Freechains!', true,
        '   --add-entry="Nickname:"'    ..
        '   --add-password="Password:"' ..
        ''
    )
    local nick,pass = table.unpack(ret)
    return cmd_host_create(port, nick, pass)
end

FC.cmd.host.nick.add = function (pub)
    local ret = FC.exe.zen('Follow '..pub, false, '--entry --text="Nickname:"')
    local nick = table.unpack(ret)
    return cmd_host_nick_add(pub,nick)
end

FC.cmd.chain.join = function ()
    local ret = FC.exe.zen('Join new chain', false, '--entry --text="Chain path:"')
    local chain = table.unpack(ret)
    return cmd_chain_join(chain)
end

FC.cmd.chain.like = function (chain, sig, n, hash)
    local like = (sig == '-') and 'dislike' or 'like'
    local Like = (sig == '-') and 'Dislike' or 'Like'
    local ret = FC.exe.zen(Like..' '..FC.short('%',hash), false, '--entry --text="Why did you '..like..' it:"')
    local why = table.unpack(ret)
    return cmd_chain_like(chain, sig, n, hash, why)
end

FC.cmd.chain.post = function (chain)
    local pay  = FC.exe._('zenity --text-info --editable --title="Publish to '..FC.nick(chain)..'"')
    local file = os.tmpname()..'.pay'
    local f    = assert(io.open(file,'w')):write(pay..'\nEOF\n')
    f:close()
    return cmd_chain_post(chain,file)
end

FC.cmd.chain.peer.add = function (chain)
    local ret   = FC.exe.zen('Add new peer to '..FC.nick(chain), false, '--entry --text="Host in format addr:port"')
    local peer  = table.unpack(ret)
    return cmd_chain_peer_add(chain,peer)
end

FC.cmd.chain.bcast = function (chain)
    local f  = io.popen('zenity --progress --percentage=0 --title="Broadcast '..FC.nick(chain)..'"', 'w')
    local co = cmd_chain_bcast(chain)
    for i,n,p in co do
        f:write('# '..p..'\n')
        f:write(math.floor(100*((i-1)/n))..'\n')
    end
    f:write('100\n')
    f:close()
end

if _REQ == 0 then
    FC.main(...)
end

return FC
