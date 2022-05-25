local args = (function()
  local parser = require('argparse')()
  parser:option('-c --cache', 'cache directory', 'cache')
  parser:option('-p --port', 'web server port', '8080'):convert(tonumber)
  return parser:parse()
end)()

local log = print

-- Tune GC very tightly. CASCs are memory hogs.
collectgarbage('setpause', 100)
collectgarbage('setstepmul', 500)

require('lfs').mkdir(args.cache)

local cascs = (function()
  local products = {
    'wow',
    'wowt',
    'wow_classic',
    'wow_classic_era',
    'wow_classic_era_ptr',
    'wow_classic_ptr',
  }
  local casc = require('casc')
  local cascs = {}
  for _, product in ipairs(products) do
    local url = 'http://us.patch.battle.net:1119/' .. product
    local bkey, cdn, ckey, version = casc.cdnbuild(url, 'us')
    if not bkey then
      print('unable to open ' .. product .. ': cannot get version')
      os.exit()
    end
    log('loading', version, url)
    local handle, err = casc.open({
      bkey = bkey,
      cache = args.cache,
      cacheFiles = true,
      cdn = cdn,
      ckey = ckey,
      locale = casc.locale.US,
      log = log,
      zerofillEncryptedChunks = true,
    })
    if not handle then
      print('unable to open ' .. product .. ': ' .. err)
      os.exit()
    end
    cascs[product] = handle
  end
  return cascs
end)()

local pathparser = (function()
  local lpeg = require('lpeg')
  local C, P, R = lpeg.C, lpeg.P, lpeg.R
  local fdid = P('/fdid/') * C(R('09') ^ 1) / tonumber
  local name = P('/name/') * C(R('az', 'AZ', '09', '__', '--', '//', '..') ^ 1)
  return P('/product/') * C(R('az', '__') ^ 1) * (fdid + name) * P(-1)
end)()

local mkres = require('http.headers').new
local listener = assert(require('http.server').listen({
  host = 'localhost',
  onerror = function(_, ctx, op, err)
    local msg = op .. ' on ' .. tostring(ctx) .. ' failed'
    if err then
      msg = msg .. ': ' .. tostring(err)
    end
    assert(io.stderr:write(msg, '\n'))
  end,
  onstream = function(_, stream)
    local req = assert(stream:get_headers())
    local product, fid = pathparser:match(req:get(':path'))
    local casc = cascs[product]
    local res = mkres()
    if not casc or not fid then
      res:append(':status', '400')
      assert(stream:write_headers(res, true))
      return
    end
    local data = casc:readFile(fid)
    if not data then
      res:append(':status', '404')
      assert(stream:write_headers(res, true))
      return
    end
    res:append(':status', '200')
    assert(stream:write_headers(res, false))
    assert(stream:write_chunk(data, true))
    log('served', product, fid)
  end,
  port = args.port,
}))
log('HTTP server ready')
pcall(function()
  listener:loop()
end)
