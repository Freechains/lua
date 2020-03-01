#!/usr/bin/env lua5.3

local optparse = require 'optparse'
local json     = require 'json'

-- TODO
-- xhost +
-- onJoin, onStart, onStop

local PATH_CFG   = os.getenv('HOME')..'/.config/freechains.json'
local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains/'
local PATH_DATA  = PATH_SHARE..'data/'
os.execute('mkdir -p '..PATH_SHARE)

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


Options:

    --address=<ip-address>      address to connect/bind (default: `localhost`)
    --port=<tcp-port>           port to connect/bind (default: `8330`)

    --help                      display this help
    --version                   display version information

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

        local chain = '/'..pub

        CFG_('save')

        EXE_FC('freechains chain join '..chain..' pubpvt '..pub..' '..pvt)
        --EXE_BG('liferea')
        --EXE('sleep 1')
        --EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')

    elseif arg[2] == 'start' then
        EXE_BG('freechains host start '..CFG.path)
        --EXE_BG('liferea')

    elseif arg[2] == 'stop' then
        --EXE('killall liferea')
        EXE_FC('freechains host stop')

    end

elseif arg[1] == 'chain' then

    if arg[2] == 'join' then

        local ret = EXE_ZEN('Join new chain', false, '--entry --text="Chain path:"')
        local chain = table.unpack(ret)

        EXE_FC('freechains chain join '..chain)
        --EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')

    elseif arg[2] == 'post' then

        local chain = arg[3]
        local pay   = EXE('zenity --text-info --editable --title="Publish to '..chain..'"')
        local file  = os.tmpname()..'.pay'
        local f     = assert(io.open(file,'w')):write(pay..'\nEOF\n')
        f:close()
        EXE_FC('freechains chain post '..chain..' file utf8 '..file, '--utf8-eof=EOF --sign='..CFG.keys.pvt)

    end


end

os.exit(0)

local DAEMON = {
    address = opts.address or 'localhost',
    port    = tonumber(opts.port) or 8330,
}

--print('>>>', table.unpack(arg))

if cmd == 'get' then
    ASR(#arg >= 2)
    local key, zeros = string.match(arg[2], '([^/]*)/?([^/]*)')
    zeros = tonumber(zeros)
    local hash = arg[3]

    local ret
    --for i=(zeros or 255), (zeros or 0), -1 do
for i=(zeros or 30), (zeros or 0), -1 do
        ret = FC.send(0x0200, {
            chain = {
                key   = key,
                zeros = i,
            },
            node    = hash,
            pub     = hash,
        }, DAEMON)
        if ret and ret.prv then
            break
        end
    end
    print(FC.tostring(ret,'plain'))

elseif cmd == 'publish' then
    ASR(#arg == 3)

    local key, zeros = string.match(arg[2], '([^/]*)/([^/]*)')

    local payload = arg[3]
    if payload == '-' then
        payload = io.stdin:read('*a')
    elseif string.sub(payload,1,1) == '+' then
        payload = string.sub(payload,2)
    else
        payload = ASR(io.open(payload)):read('*a')
    end

    FC.send(0x0300, {
        chain = {
            key   = key,
            zeros = ASR(tonumber(zeros)),
        },
        payload = payload,
        sign    = opts.sign,
    }, DAEMON)

elseif cmd == 'remove' then
    ASR(#arg == 3)

    local key, zeros = string.match(arg[2], '([^/]*)/([^/]*)')

    FC.send(0x0300, {
        chain = {
            key   = key,
            zeros = ASR(tonumber(zeros)),
        },
        removal = arg[3],
    }, DAEMON)

elseif cmd == 'subscribe' then
    ASR(#arg >= 2)

    local key, zeros = string.match(arg[2], '([^/]*)/?([^/]*)')
    zeros = tonumber(zeros) or 0

    local peers = {}
    for i=3, #arg do
        local address, port = string.match(arg[i], '([^:]*):?(.*)')
        port = tonumber(port) or 8330
        peers[#peers+1] = {
            address = address,
            port    = port,
        }
    end

    FC.send(0x0400, {
        chain = {
            key   = key,
            zeros = zeros,
            peers = peers,
        }
    }, DAEMON)

elseif cmd == 'configure' then
    local sub = arg[2]
    ASR(sub=='get' or sub=='set')

    CFG = FC.send(0x0500, nil, DAEMON)

--[[
    if sub == 'sync' then
        ASR(#arg == 2)

        -- passphrase
        io.stdout:write('Passphrase (minimum of 32 characters): ')
        local passphrase = io.read()
        --assert(string.len(passphrase) >= 32)

        -- peer
        io.stdout:write('Peer (IP:port): ')
        local peer = io.read()
        local address, port = string.match(peer, '([^:]*):(.*)')
        if not address then
            address = peer
        end

        -- filename
        io.stdout:write('Configuration File [cfg/config.lua]: ')
        local filename = io.read()
        if filename == '' then
            filename = 'cfg/config.lua'
        end

        -- write
        CFG = {
            sync = {
                passphrase = passphrase,
                peer = {
                    address = assert(address),
                    port    = port and assert(tonumber(port)) or 8330,
                },
            },
        }
        FC.cfg_write(filename)
]]

    if sub=='get' and #arg==2 then
        print(FC.tostring(CFG,'plain'))
    else
        ASR(#arg == 3)

        local field, op, value = string.match(arg[3], '([^-+=]*)(-?+?=?)(.*)')
        str = 'CFG.'..field

        if sub == 'get' then
            print(FC.tostring( assert(load('return '..str))() , 'plain' ))
        else
            ASR(op=='=' or op=='+=' or op=='-=')
            ASR(value ~= '')

            -- if value evaluates to nil, treat it as a string
            -- handle nil and false as special cases
            if value~='nil' and value~='false' then
                value = value..' or "'..value..'"'
            end

            if op == '=' then
                assert(load(str..' = '..value))()
            elseif op == '+=' then
                assert(load(str..'[#'..str..'+1] = '..value))()
            elseif op == '-=' then
                assert(load('table.remove('..str..', assert(tonumber('..value..')))'))()
            end

            FC.send(0x0500, CFG, DAEMON)
        end
    end

elseif cmd == 'listen' then
    ASR(#arg <= 2)
    local chain
    if #arg == 2 then
        local key, zeros = string.match(arg[2], '([^/]*)/?([^/]*)')
        zeros = tonumber(zeros)
        chain = {
            key   = key,
            zeros = zeros,
        }
    else
        chain = nil
    end

    FC.send(0x0600, {
        chain = chain,
    }, DAEMON)

elseif cmd == 'daemon' then
    ASR(#arg >= 2)
    local _, sub, cfg = table.unpack(arg)
    if sub == 'start' then
        ASR(#arg == 3)
        os.execute('freechains-daemon '..cfg..' '..DAEMON.address..' '..DAEMON.port)
    else
        ASR(sub == 'stop')
        FC.send(0x0000, '', DAEMON)
    end

elseif cmd == 'crypto' then
    local _, sub, tp = table.unpack(arg)

    if sub == 'create' then
        ASR(#arg == 3)

        if tp=='x-public' or tp=='x-private' then
            ASR(opts.passphrase, 'missing `--passphrase`')
        end

        local ret = FC.send(0x0700, {
            create     = tp,
            passphrase = opts.passphrase,
        }, DAEMON)

        if tp == 'public-private' then
            print(ret.public)
            print(ret.private)
        elseif tp == 'x-public' then
            print(ret.public)
        elseif tp == 'x-private' then
            print(ret.private)
        else
            assert(tp == 'shared')
            print(ret)
        end

    elseif sub=='encrypt' or sub=='decrypt' then
        local _,key,pub,pvt,payload

        if tp == 'shared' then
            ASR(#arg == 5)
            _,_,_,key,payload = table.unpack(arg)
        elseif tp=='sealed' and sub=='encrypt' then
            _,_,_,pub,payload = table.unpack(arg)
        else
            _,_,_,pub,pvt,payload = table.unpack(arg)
        end

        if payload == '-' then
            payload = io.stdin:read('*a')
        elseif string.sub(payload,1,1) == '+' then
            payload = string.sub(payload,2)
        else
            payload = ASR(io.open(payload)):read('*a')
        end

        local ret = FC.send(0x0700, {
            [sub]   = tp,
            payload = payload,
            key     = key,
            pub     = pub,
            pvt     = pvt,
        }, DAEMON)
        io.stdout:write(tostring(ret))

    else
        ASR(false)
    end

else
    ASR(false)
end
