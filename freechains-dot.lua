#!/usr/bin/env lua5.3

-- lua5.3 dot.lua /tmp/freechains/8400/chains/ | dot -Tpng -o out.png

local json = require 'json'

DIR   = ...
CHAIN = json.decode(assert(io.open(DIR..'/chain')):read('*a'))
NODES = {}
CONNS = {}

function sub (str)
    return string.sub(str,1,9)
end

function out ()
    local f = io.stdout
    f:write([[
digraph graphname {
    rankdir=LR;  // Rank Direction Left to Right
    nodesep=1.0 // increases the separation between nodes
    edge [];
    //splines = true;
    ]]..table.concat(NODES,'\n    ')..[[

    ]]..table.concat(CONNS,'\n    ')..[[

}
]])
    f:close()
end

function one (hash)
    if NODES[hash] then
        return
    end
    NODES[hash] = true

    local blk = json.decode(assert(io.open(DIR..'/blocks/'..hash..'.blk')):read('*a'))

    local h   = blk.immut
    local ref = (h.like == json.util.null) and '' or sub(h.like.hash)
    local t   = math.floor(blk.immut.time)
    local lik = (type(h.like)=='table' and h.like.n) or '---'

    NODES[#NODES+1] = '_'..hash..'[label="'..sub(hash)..'\n'..blk.pay..'\n'..ref..'\n'..lik..'\n'..t..'"];'

    for _,back in ipairs(blk.fronts) do
        CONNS[#CONNS+1] = '_'..hash..' -> _'..back
    end
    go(blk.fronts)
end

function go (fronts)
    for _, hash in ipairs(fronts) do
        one(hash)
    end
end

--go(CHAIN.heads)
one('0_'..CHAIN.hash)
out()
