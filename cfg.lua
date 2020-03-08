#!/usr/bin/env lua5.3

local optparse = require 'optparse'
local json     = require 'json'

local share = os.getenv('HOME')..'/.local/share/freechains/'

function split (sep, str)
    local ret = {}
    for it in string.gmatch(str, '([^'..sep..']+)') do
        table.insert(ret, it)
    end
    return ret
end

local FC ; FC = {

-------------------------------------------------------------------------------

    path = {
        cfg   = os.getenv('HOME')..'/.config/freechains.json',
        share = share,
        data  = share..'/data/',
        cbs   = share..'/callbacks.lua',
    },

    main = function (...)
        local cmd = FC.cmd
        local str = ''
        for i=1, select('#',...) do
            assert(type(cmd) == 'table', 'invalid command: '..str)
            local v = select(i, ...)
            str = str .. (i==1 and '' or '.') .. v
            cmd = cmd[v]
            if type(cmd) == 'function' then
                cmd(select(i+1, ...))
                return
            end
        end
        error('incomplete command: '..str)
    end,

    short = function (pre,hash)
        local nick = FC.CFG.nicks[hash]
        if pre=='@' and nick then
            return '@'..nick
        end
        return pre..string.sub(hash,1,9)
    end,

    chain2nick = function (chain)
        local pub  = string.sub(chain,2)
        local nick = FC.CFG.nicks[pub]
        return (nick and '@'..nick) or chain
    end,

-------------------------------------------------------------------------------

    CFG = {
        port   = 8330,
        nick   = 'anon',
        keys   = {
            pub = nil,
            pvt = nil,
        },
        chains = {},
        nicks  = {},
    },

    cfg = {
        save = function ()
            os.rename(FC.path.cfg,FC.path.cfg..'.bak')
            local f = assert(io.open(FC.path.cfg,'w'))
            f:write(json.encode(FC.CFG)..'\n')
            f:close()
        end,

        load = function ()
            local f = io.open(FC.path.cfg)
            if f then
                FC.CFG = json.decode(f:read('*a'))
                f:close()
            end
        end,

        chain = function (chain)
            local t = FC.CFG.chains[chain] or { peers={} }
            FC.CFG.chains[chain] = t
            FC.cfg.save()
            return t
        end,

        peers = function (chain)
            local ps = {}
            for p in pairs(FC.cfg.chain(chain).peers) do
                ps[#ps+1] = p
            end
            return ps
        end,
    },

-------------------------------------------------------------------------------

    exe = {
        _ = function (cmd)
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
        end,

        bg = function (cmd)
            io.popen(cmd)
        end,

        fc = function (cmd,opts)
            opts = opts or ''
            return FC.exe._('freechains --host=localhost:'..FC.CFG.port..' '..opts..' '..string.sub(cmd,12))
        end,
    },

-------------------------------------------------------------------------------

    cmd = {
        host = {
            drop = function ()
                os.execute('rm -Rf '..FC.path.cfg..' '..FC.path.data)
            end,
            
            create = function (port, nick, pass)
                port = assert(tonumber(port or 8330), 'invalid port number')
                assert(not string.find(nick,'%W'), 'nickname should only contain alphanumeric characters')

                FC.CFG.port = assert(tonumber(port or 8330), 'invalid port number')
                FC.CFG.nick = nick

                FC.exe._('freechains host create '..FC.path.data..' '..FC.CFG.port)
                FC.exe.bg('freechains host start '..FC.path.data)
                FC.exe._('sleep 0.5')

                local ret = FC.exe.fc('freechains crypto create pubpvt '..pass)
                local pub,pvt = string.match(ret, '^([^\n]*)\n(.*)$')

                FC.CFG.keys = { pub=pub, pvt=pvt }
                FC.CFG.nicks[pub] = nick
                FC.CFG.nicks[nick] = pub
                FC.cfg.save()

                FC.exe.fc('freechains chain join /'..pub..' '..pub)
                return pub
            end,

            start = function ()
                FC.exe.bg('freechains host start '..FC.path.data)
            end,

            stop = function ()
                FC.exe.fc('freechains host stop')
            end,

            nick = {
                add = function (pub, nick)
                    FC.CFG.nicks[pub] = nick
                    FC.CFG.nicks[nick] = pub
                    FC.cfg.save()
                    FC.exe.fc('freechains chain join /'..pub..' '..pub)
                end,
            },
        },

-------------------------------------------------------------------------------

        chain = {
            join = function (chain)
                FC.exe.fc('freechains chain join '..chain)
                return chain
            end,

            post = function (chain_nick, file)
                function unnick (chain_nick)
                    if string.sub(chain_nick,1,1) == '@' then
                        return assert(FC.CFG.nicks[string.sub(chain_nick,2)], 'unknown nick '..chain_nick)
                    else
                        return chain_nick
                    end
                end
                local chain = unnick(chain_nick)
                FC.exe.fc('freechains chain post '..chain..' file utf8 '..file, '--utf8-eof=EOF --sign='..FC.CFG.keys.pvt)
            end,

            like = function (chain, sig, n, hash, why)
                FC.exe.fc('freechains chain like post '..chain..' '..sig..' '..n..' '..hash,
                            ' --sign='..FC.CFG.keys.pvt..
                            ' --why="'..why..'"')
            end,

            accept = function (chain, hash)
                FC.exe.fc('freechains chain accept '..chain..' '..hash)
            end,
            remove = function (chain, hash)
                FC.exe.fc('freechains chain remove '..chain..' '..hash)
            end,

            peer = {
                add = function (chain, peer)
                    local t = FC.cfg.chain(chain).peers
                    t[peer] = true
                    FC.cfg.save()
                end,
            },

            bcast = function (chain)
                return coroutine.wrap (
                    function ()
                        local ps = FC.cfg.peers(chain)
                        for i,p in ipairs(ps) do
                            coroutine.yield(i, #ps, p)
                            FC.exe.fc('freechains chain send '..chain..' '..p)
                        end
                    end
                )
            end,

            iter = {
                block = function (chain)
                    local visited = {}
                    local heads   = {}

                    local function one (hash,init)
                        if visited[hash] then return end
                        visited[hash] = true

                        --LOG:write('freechains chain get '..chain..' '..hash..'\n')
                        local ret = FC.exe.fc('freechains chain get '..chain..' '..hash)

                        local blk = json.decode(ret)
                        if not init then
                            coroutine.yield(blk)
                        end

                        for _, front in ipairs(blk.fronts) do
                            one(front)
                        end

                        if #blk.fronts == 0 then
                            heads[hash] = true
                        end
                    end

                    return coroutine.wrap (
                        function ()
                            local cfg = FC.cfg.chain(chain)
                            if cfg.heads and next(cfg.heads) then
                                for hash in pairs(cfg.heads) do
                                    one(hash,true)
                                end
                            else
                                local hash = FC.exe.fc('freechains chain genesis '..chain)
                                one(hash,true)
                            end

                            local stable = split(' ', FC.exe.fc('freechains chain heads stable '..chain))
                            local t = {}
                            for _,hash in ipairs(stable) do
                                t[hash] = true
                            end

                            cfg.heads = t
                            FC.cfg.save()
                        end
                    )
                end,

                state = function (chain, state)
                    local ret = FC.exe.fc('freechains chain state list '..chain..' '..state)
                    ret = split(' ', ret)

                    return coroutine.wrap(
                        function ()
                            for _,hash in ipairs(ret) do
                                local j = FC.exe.fc('freechains chain state get '..chain..' '..state..' '..hash)
                                local blk = json.decode(j)
                                coroutine.yield(blk)
                            end
                        end
                    )
                end,
            },
        },
    },
}

os.execute('mkdir -p '..FC.path.share)
pcall(dofile, FC.path.cbs)
FC.cfg.load()

if not _REQ then
    FC.main(...)
end

return FC
