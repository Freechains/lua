#!/usr/bin/env lua5.3

local optparse = require 'optparse'
local json     = require 'json'

-- TODO
-- xhost +

local PATH_CFG   = os.getenv('HOME')..'/.config/freechains.json'
local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains/'
local PATH_DATA  = PATH_SHARE..'/data/'
local PATH_CBS   = PATH_SHARE..'/callbacks.lua'
os.execute('mkdir -p '..PATH_SHARE)
pcall(dofile, PATH_CBS)

-------------------------------------------------------------------------------

local help = [=[
freechains-ui 0.2

Usage: freechains-ui [<options>] <command> <arguments>

$ freechains-ui host create [<port>]    | nick password
$ freechains-ui host drop
$ freechains-ui host start
$ freechains-ui host stop
$ freechains-ui host nick add <pub>     | nick

$ freechains-ui chain join <chain>      | path
$ freechains-ui chain post <chain>      | payload
$ freechains-ui chain peer add <chain>  | host
$ freechains-ui chain bcast <chain>
$ freechains-ui chain atom <chain>

More Information:

    http://www.freechains.org/

    Please report bugs at <http://github.com/Freechains/freechains-ui>.
]=]

local parser = optparse(help)
local arg, opts = parser:parse(_G.arg)

-------------------------------------------------------------------------------

local CFG = {
    path   = PATH_DATA,
    nick   = 'anon',
    keys   = {
        pub = nil,
        pvt = nil,
    },
    chains = {},
    nicks  = {},
}

function CFG_ (cmd)
    if cmd == 'load' then
        local f = io.open(PATH_CFG)
        if f then
            CFG = json.decode(f:read('*a'))
            f:close()
        end
    else
        os.rename(PATH_CFG,PATH_CFG..'.bak')
        local f = assert(io.open(PATH_CFG,'w'))
        f:write(json.encode(CFG)..'\n')
        f:close()
    end
end

function CFG_chain (chain)
    local t = CFG.chains[chain] or { peers={} }
    CFG.chains[chain] = t
    CFG_('save')
    return t
end

function CFG_peers (chain)
    local ps = {}
    for p in pairs(CFG_chain(chain).peers) do
        ps[#ps+1] = p
    end
    return ps
end

CFG_('load')

-------------------------------------------------------------------------------

function EXE (cmd)
    local f = io.popen(cmd)
    local ret = f:read("*a")
    local ok = f:close()
    if ok then
        if string.sub(ret,-1,-1)=='\n' then
            ret = string.sub(ret,1,-2)  -- except "--text-info" enters here
        end
        return ret
    else
        io.stderr:write('command aborted: '..cmd..'\n')
        os.exit(1)
        return ok, 'EXE: '..cmd
    end
end

function EXE_BG (cmd)
    io.popen(cmd)
end

function EXE_FC (cmd,opts)
    opts = opts or ''
    return EXE('freechains --host=localhost:'..CFG.port..' '..opts..' '..string.sub(cmd,12))
end

function split (str)
    local ret = {}
    for it in string.gmatch(str, "([^\t]*)") do
        table.insert(ret, it)
    end
    return ret
end

function EXE_ZEN (title, forms, cmd)
    forms = forms and '--forms --separator="\t"' or ''
    local z = (
        'zenity'                    ..
        '   '..forms                ..
        '   --title="'..title..'"'  ..
        '   '..cmd
    )
    local ret = EXE(z)
    return ret and split(ret)
end

-------------------------------------------------------------------------------

CBS = callbacks or {
    onHostCreate = function (pub) end,
    onHostStart  = function () end,
    onHostStop   = function () end,
    onChainJoin  = function (chain) end,
    onChainPost  = function (chain) end,
}

-------------------------------------------------------------------------------

if arg[1] == 'host' then

    if arg[2] == 'drop' then
        os.execute('rm -Rf '..PATH_CFG..' '..PATH_DATA)
        os.exit(0)
    
    elseif arg[2] == 'create' then

        CFG.port = assert(tonumber(arg[3] or 8330), 'invalid port number')

        local ret = EXE_ZEN('Welcome to Freechains!', true,
            '   --add-entry="Nickname:"'    ..
            '   --add-password="Password:"' ..
            ''
        )

        local nick,pass = table.unpack(ret)
        assert(not string.find(nick,'%W'), 'nickname should only contain alphanumeric characters')
        CFG.nick = nick

        EXE('freechains host create '..CFG.path..' '..CFG.port)
        EXE_BG('freechains host start '..CFG.path)
        EXE('sleep 0.5')

        local ret = EXE_FC('freechains crypto create pubpvt '..pass)
        local pub,pvt = string.match(ret, '^([^\n]*)\n(.*)$')
        CFG.keys = { pub=pub, pvt=pvt }
        CFG.nicks[pub] = nick
        CFG.nicks[nick] = pub
        CFG_('save')

        EXE_FC('freechains chain join /'..pub..' pubpvt '..pub..' '..pvt)
        CBS.onHostCreate(pub)
        os.exit(0)

    elseif arg[2] == 'start' then
        EXE_BG('freechains host start '..CFG.path)
        CBS.onHostStart()
        os.exit(0)

    elseif arg[2] == 'stop' then
        EXE_FC('freechains host stop')
        CBS.onHostStop()
        os.exit(0)

    elseif arg[2] == 'nick' then

        if arg[3] == 'add' then

            local pub = arg[4]
            local ret = EXE_ZEN('Follow '..pub, false, '--entry --text="Nickname:"')
            local nick = table.unpack(ret)

            CFG.nicks[pub] = nick
            CFG.nicks[nick] = pub
            CFG_('save')

            EXE_FC('freechains chain join /'..pub..' pubpvt '..pub)
            CBS.onChainJoin('/'..pub)
            os.exit(0)

        end

    end

elseif arg[1] == 'chain' then

    if arg[2] == 'join' then

        local ret = EXE_ZEN('Join new chain', false, '--entry --text="Chain path:"')
        local chain = table.unpack(ret)

        EXE_FC('freechains chain join '..chain)
        CBS.onChainJoin(chain)
        os.exit(0)

    elseif arg[2] == 'post' then

        function UNNICK (nick)
            if string.sub(nick,1,1) == '@' then
                return assert(CFG.nicks[string.sub(nick,2)], 'unknown nick '..nick)
            else
                return nick
            end
        end

        local chain = UNNICK(arg[3])
        local pay   = EXE('zenity --text-info --editable --title="Publish to '..chain..'"')
        local file  = os.tmpname()..'.pay'
        local f     = assert(io.open(file,'w')):write(pay..'\nEOF\n')
        f:close()
        EXE_FC('freechains chain post '..chain..' file utf8 '..file, '--utf8-eof=EOF --sign='..CFG.keys.pvt)
        CBS.onChainPost(chain)
        os.exit(0)

    elseif arg[2] == 'peer' then
        if arg[3] == 'add' then

            local chain = arg[4]
            local ret   = EXE_ZEN('Add new peer to '..chain, false, '--entry --text="Host in format addr:port"')
            local peer  = table.unpack(ret)

            local t = CFG_chain(arg[4]).peers
            t[peer] = true
            CFG_('save')
            os.exit(0)
        end

    elseif arg[2] == 'bcast' then

        local chain = arg[3]
        local f = io.popen('zenity --progress --percentage=0 --title="Broadcast '..chain..'"', 'w')
        local ps = CFG_peers(chain)
        for i,p in ipairs(ps) do
            f:write('# '..p..'\n')
            --EXE('sleep 1')
            EXE_FC('freechains chain send '..chain..' '..p)
            f:write(math.floor(100*(i/#ps))..'\n')
        end
        f:close()
        os.exit(0)

    elseif arg[2] == 'atom' then

        function hash2hex (hash)
            local ret = ''
            for i=1, string.len(hash) do
                ret = ret .. string.format('%02X', string.byte(string.sub(hash,i,i)))
            end
            return ret
        end

        function escape (html)
            return (string.gsub(html, "[}{\">/<'&]", {
                ["&"] = "&amp;",
                ["<"] = "&lt;",
                [">"] = "&gt;",
                ['"'] = "&quot;",
                ["'"] = "&#39;",
                ["/"] = "&#47;"
            }))
        end -- https://github.com/kernelsauce/turbo/blob/master/turbo/escape.lua

        function iter (chain)
            local visited = {}
            local heads   = {}

            local function one (hash,init)
                if visited[hash] then return end
                visited[hash] = true

                --LOG:write('freechains chain get '..chain..' '..hash..'\n')
                local ret = EXE_FC('freechains chain get '..chain..' '..hash)

                local block = json.decode(ret)
                if not init then
                    coroutine.yield(block)
                end

                for _, front in ipairs(block.fronts) do
                    one(front)
                end

                if #block.fronts == 0 then
                    heads[#heads+1] = hash
                end
            end

            return coroutine.wrap(
                function ()
                    local cfg = CFG_chain(chain)
                    if cfg.heads then
                        for _,hash in ipairs(cfg.heads) do
                            one(hash,true)
                        end
                    else
                        local hash = EXE_FC('freechains chain genesis '..chain)
                        one(hash,true)
                    end

                    cfg.heads = heads
                    CFG_('save')
                end
            )
        end

        -----------------------------------------------------------------------

        function NICK (chain)
            local pub  = string.sub(chain,2)
            local nick = CFG.nicks[pub]
            return (nick and '@'..nick) or chain
        end

        function MINE (chain)
            return (chain == '/'..CFG.keys.pub)
        end

        -----------------------------------------------------------------------

        local chain = arg[3]

        TEMPLATES =
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
                        freechains:__CHAIN__/__HASH__/
                    </id>
                    <published>__DATE__</published>
                    <content type="html">__PAYLOAD__</content>
                </entry>
            ]],
        }

        -- TODO: hacky, "plain" gsub
        gsub = function (a,b,c)
            return string.gsub(a, b, function() return c end)
        end

        local entries = {}

        for block in iter(chain) do
            local payload = block.hashable.payload
            local title = escape(string.match(payload,'([^\n]*)'))
            local pub = block.signature and block.signature.pub
            local author = 'Signed by '
            do
                if block.signature == json.util.null then
                    author = author .. 'Not signed'
                else
                    local nick = CFG.nicks[pub]
                    if nick then
                        author = author .. '@'..nick
                    else
                        --author = author .. '[@'..string.sub(pub,1,9)..'](freechains://nick-'..pub..')'
                        author = author .. '<a href="freechains://host-nick-add-'..pub..'">@'..string.sub(pub,1,9)..'</a>'
                    end
                end
            end

            payload = payload .. [[


-------------------------------------------------------------------------------

]]..author..[[

<a href=xxx> like </a>

<a href=yyy> dislike </a>

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

            payload = escape(payload)

            entry = TEMPLATES.entry
            entry = gsub(entry, '__TITLE__',   title)
            entry = gsub(entry, '__CHAIN__',   chain)
            entry = gsub(entry, '__HASH__',    block.hash)
            entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', block.hashable.timestamp))
            entry = gsub(entry, '__PAYLOAD__', payload)
            entries[#entries+1] = entry
        end

        -- MENU
        do
            local ps = table.concat(CFG_peers(chain),',')
            local add = [[
<a href="freechains://chain-peer-add-]]..chain..[[">[add]</a>
]]

            entry = TEMPLATES.entry
            entry = gsub(entry, '__TITLE__',   'Menu')
            entry = gsub(entry, '__CHAIN__',   chain)
            entry = gsub(entry, '__HASH__',    hash2hex(string.rep('\0',32)))
            entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', 25000))
            entry = gsub(entry, '__PAYLOAD__', escape([[
<ul>
]]..(not MINE(chain) and '' or [[
<li> <a href="freechains://chain-join">[X]</a> join new chain
]])..[[
<li> <a href="freechains://chain-post-]]..chain..[[">[X]</a> post to "]]..NICK(chain)..[["
<li> <a href="freechains://chain-bcast-]]..chain..[[">[X]</a> broadcast to peers ]]..add..[[ (]]..ps..[[)
</ul>
]]))
            entries[#entries+1] = entry
        end

        feed = TEMPLATES.feed
        feed = gsub(feed, '__TITLE__',   NICK(chain))
        feed = gsub(feed, '__UPDATED__', os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()))
        feed = gsub(feed, '__CHAIN__',   chain)
        feed = gsub(feed, '__ENTRIES__', table.concat(entries,'\n'))

        f = io.stdout --assert(io.open(dir..'/'..key..'.xml', 'w'))
        f:write(feed)
        os.exit(0)

    end

end

::ERROR::
io.stderr:write('invalid command: '..table.concat({...},' ')..'\n')
os.exit(1)
