#!/usr/bin/env lua5.3

local optparse = require 'optparse'
local json     = require 'json'

-- TODO
-- xhost +
-- onJoin, onStart, onStop

local PATH_CFG   = os.getenv('HOME')..'/.config/freechains.json'
local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains/'
local PATH_DATA  = PATH_SHARE..'/data/'
local PATH_CBS   = PATH_SHARE..'/callbacks.lua'
os.execute('mkdir -p '..PATH_SHARE)
pcall(dofile, PATH_CBS)

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
        local f = assert(io.open(PATH_CFG,'w'))
        f:write(json.encode(CFG)..'\n')
        f:close()
    end
end

CFG_('load')

-------------------------------------------------------------------------------

local help = [=[
freechains-ui 0.2

Usage: freechains-ui [<options>] <command> <arguments>

$ freechains-ui host create [<port>]
$ freechains-ui host drop
$ freechains-ui host start
$ freechains-ui host stop

$ freechains-ui chain join <chain> ...
$ freechains-ui chain atom <chain>

More Information:

    http://www.freechains.org/

    Please report bugs at <http://github.com/Freechains/freechains-ui>.
]=]

local parser = optparse(help)
local arg, opts = parser:parse(_G.arg)

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
        CFG_('save')

        EXE_FC('freechains chain join /'..pub..' pubpvt '..pub..' '..pvt)
        CBS.onHostCreate(pub)

    elseif arg[2] == 'start' then
        EXE_BG('freechains host start '..CFG.path)
        CBS.onHostStart()

    elseif arg[2] == 'stop' then
        EXE_FC('freechains host stop')
        CBS.onHostStop()

    end

elseif arg[1] == 'chain' then

    if arg[2] == 'join' then

        local ret = EXE_ZEN('Join new chain', false, '--entry --text="Chain path:"')
        local chain = table.unpack(ret)

        EXE_FC('freechains chain join '..chain)
        CBS.onChainJoin(chain)

    elseif arg[2] == 'post' then

        local chain = arg[3]
        local pay   = EXE('zenity --text-info --editable --title="Publish to '..chain..'"')
        local file  = os.tmpname()..'.pay'
        local f     = assert(io.open(file,'w')):write(pay..'\nEOF\n')
        f:close()
        EXE_FC('freechains chain post '..chain..' file utf8 '..file, '--utf8-eof=EOF --sign='..CFG.keys.pvt)
        CBS.onChainPost(chain)

    end


end
