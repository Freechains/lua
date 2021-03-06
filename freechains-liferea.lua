#!/usr/bin/env lua5.3

-- TODO
-- xhost +

_REQ = _REQ and (_REQ + 1) or 1
local FC = require 'freechains.ui'

local cmd = (...)
if string.sub(cmd,1,13) ~= 'freechains://' then
    os.execute('xdg-open '..cmd)
    os.exit(0)
end

local cmd_host_create   = FC.cmd.host.create
local cmd_host_start    = FC.cmd.host.start
local cmd_host_stop     = FC.cmd.host.stop
local cmd_host_nick_add = FC.cmd.host.nick.add
local cmd_chain_join    = FC.cmd.chain.join

function FC.cmd.host.create (port)
    local pub = cmd_host_create(port)
    FC.exe.bg('liferea')
    FC.exe._('sleep 1')
    FC.exe._('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain.atom./'..pub..'"')
end

function FC.cmd.host.start (port)
    cmd_host_start()
    FC.exe.bg('liferea')
end

function FC.cmd.host.stop (port)
    cmd_host_stop()
    FC.exe._('killall liferea')
end

function FC.cmd.host.nick.add (pub)
    cmd_host_nick_add(pub)
    FC.exe._('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain.atom./'..pub..'"')
end

function FC.cmd.chain.join ()
    local chain = cmd_chain_join()
    FC.exe._('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain.atom.'..chain..'"')
end

-------------------------------------------------------------------------------

local TEMPLATES =
{
    feed = [[
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>__TITLE__</title>
            <updated>__UPDATED__</updated>
            <id>
                freechains:__CHAIN__/
            </id>
        __ENTRIES__
        </feed>
    ]],
    entry = [[
        <entry>
            <title>__TITLE__</title>
            <id>
                freechains:__CHAIN__/__HASH__/__UPDATED__
            </id>
            <published>__DATE__</published>
            <updated>__UPDATED__</updated>
            <content type="html">__PAYLOAD__</content>
        </entry>
    ]],
}

-- TODO: hacky, "plain" gsub
local function GSUB (a,b,c)
    return string.gsub(a, b, function() return c end)
end

local function ESCAPE (html)
    return (string.gsub(html, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end -- https://github.com/kernelsauce/turbo/blob/master/turbo/escape.lua

function html (chain, blk, state)
    local payload = blk.immut.payload

    local like = blk.immut.like
    if like ~= json.util.null then
        local pre = (like.type == 'PUBKEY') and '@' or '%'
        payload = like.n..' '..FC.short(pre,like.ref)..'\n\n'..payload
    end

    local title = ESCAPE(string.match(payload,'([^\n]*)'))
    local pub = blk.sign and blk.sign.pub
    local author do
        if blk.sign == json.util.null then
            author = 'anonymous'
        else
            local short = FC.short('@',pub)
            if FC.CFG.nicks[pub] then
                author = short
            else
                author = '<a href="freechains://host.nick.add.'..pub..'">'..short..'</a>'
            end
        end
    end

    payload = payload .. [[


-------------------------------------------------------------------------------

Post ]]..FC.short('%',blk.hash)..[[


[<a href=freechains://chain.like.]]  ..chain..'.-.1000.'..blk.hash..[[> - </a>
 like
 <a href=freechains://chain.like.]]  ..chain..'.+.1000.'..blk.hash..[[> + </a>]

[<a href=freechains://chain.remove.]]..chain..'.'..blk.hash..[[> - </a>
 post
 <a href=freechains://chain.accept.]]..chain..'.'..blk.hash..[[> + </a>]

By ]]..author..[[
]]

    -- markdown
    if true then
        do
            local tmp = os.tmpname()
            local md = assert(io.popen('pandoc -r markdown -w html > '..tmp, 'w'))
            md:write(payload)
            assert(md:close())
            local html = assert(io.open(tmp))
            payload = html:read('*a')
            html:close()
            os.remove(tmp)
        end
    end

    payload = ESCAPE(payload)

    local pre = {
        block = '[!]',
        tine  = '[?]',
        rem   = '[-]',
    }

    local rep = '['..FC.exe.fc('freechains chain like get '..chain..' '..blk.hash)..']'

    local entry = TEMPLATES.entry
    entry = GSUB(entry, '__TITLE__',   pre[state]..' '..rep..' '..title)
    entry = GSUB(entry, '__CHAIN__',   chain)
    entry = GSUB(entry, '__HASH__',    blk.hash)
    entry = GSUB(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', blk.immut.timestamp))
    entry = GSUB(entry, '__UPDATED__', os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()))
    entry = GSUB(entry, '__PAYLOAD__', payload)
    return entry
end

function FC.cmd.chain.atom (chain)

    local function HASH2HEX (hash)
        local ret = ''
        for i=1, string.len(hash) do
            ret = ret .. string.format('%02X', string.byte(string.sub(hash,i,i)))
        end
        return ret
    end

    local function MINE (chain)
        return (chain == '/'..FC.CFG.keys.pub)
    end

    -----------------------------------------------------------------------

    local entries = {}
    local likes   = {}
    local function l (blk)
        local like = blk.immut.like
        if like ~= json.util.null then
            if like.type == 'POST' then
                likes[#likes+1] = like.ref
            end
        end
    end

    for blk in FC.cmd.chain.iter.block(chain) do
        entries[#entries+1] = html(chain, blk, 'block')
        l(blk)
    end
    for blk in FC.cmd.chain.iter.state(chain, 'tine') do
        entries[#entries+1] = html(chain, blk, 'tine')
        l(blk)
    end
    for blk in FC.cmd.chain.iter.state(chain, 'rem') do
        entries[#entries+1] = html(chain, blk, 'rem')
        l(blk)
    end

    for _,hash in ipairs(likes) do
        local ret = FC.exe.fc('freechains chain get '..chain..' '..hash)
        if ret ~= '' then
            local blk = json.decode(ret)
            entries[#entries+1] = html(chain, blk, 'block')
        end
    end

    -- MENU
    do
        local ps = table.concat(FC.cfg.peers(chain),',')
        local add = [[
<a href="freechains://chain.peer.add.]]..chain..[[">[add]</a>
]]

        local entry = TEMPLATES.entry
        entry = GSUB(entry, '__TITLE__',   'Menu')
        entry = GSUB(entry, '__CHAIN__',   chain)
        entry = GSUB(entry, '__HASH__',    HASH2HEX(string.rep('\0',32)))
        entry = GSUB(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', 25000))
        entry = GSUB(entry, '__PAYLOAD__', ESCAPE([[
<ul>
]]..(not MINE(chain) and '' or [[
<li> <a href="freechains://chain.join">[X]</a> join new chain
]])..[[
<li> <a href="freechains://chain.post.]]..chain..[[">[X]</a> post to "]]..FC.chain2nick(chain)..[["
<li> <a href="freechains://chain.bcast.]]..chain..[[">[X]</a> broadcast to peers ]]..add..[[ (]]..ps..[[)
</ul>
]]))
        entries[#entries+1] = entry
    end

    local feed = TEMPLATES.feed
    feed = GSUB(feed, '__TITLE__',   FC.chain2nick(chain))
    feed = GSUB(feed, '__UPDATED__', os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()))
    feed = GSUB(feed, '__CHAIN__',   chain)
    feed = GSUB(feed, '__ENTRIES__', table.concat(entries,'\n'))

    f = io.stdout --assert(io.open(dir..'/'..key..'.xml', 'w'))
    f:write(feed)

end

cmd = split('.', string.sub(cmd,14))
--print(table.unpack(cmd))
FC.main(table.unpack(cmd))
