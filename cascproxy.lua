local args = (function()
  local parser = require('argparse')()
  parser:option('-p --product', 'WoW product'):count(1):choices({
    'wow',
    'wowt',
    'wow_classic',
    'wow_classic_era',
    'wow_classic_era_ptr',
    'wow_classic_ptr',
  })
  parser:option('--port', 'port to listen on', 8080)
  parser:flag('-v --verbose', 'verbose printing')
  return parser:parse()
end)()

local log = args.verbose and print or function() end

local casc = (function()
  local casc = require('casc')
  local url = 'http://us.patch.battle.net:1119/' .. args.product
  local bkey, cdn, ckey, version = casc.cdnbuild(url, 'us')
  if not bkey then
    print('unable to open ' .. args.product .. ': cannot get version')
    os.exit()
  end
  log('loading', version, url)
  local handle, err = casc.open({
    bkey = bkey,
    cache = 'cache',
    cacheFiles = true,
    cdn = cdn,
    ckey = ckey,
    locale = casc.locale.US,
    log = log,
    zerofillEncryptedChunks = true,
  })
  if not handle then
    print('unable to open ' .. args.product .. ': ' .. err)
    os.exit()
  end
  return handle
end)()

local pathparser = (function()
  local lpeg = require('lpeg')
  local C, P, R = lpeg.C, lpeg.P, lpeg.R
  local fdid = P('/fdid/') * C(R('09') ^ 1) / tonumber
  local name = P('/name/') * C(R('az', 'AZ', '09', '__', '--', '//', '..') ^ 1)
  return (fdid + name) * P(-1)
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
    local fid = pathparser:match(req:get(':path'))
    local res = mkres()
    if not fid then
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
    res:append('content-type', 'text/plain')
    assert(stream:write_headers(res, false))
    assert(stream:write_chunk(data, true))
  end,
  port = args.port,
}))
pcall(function()
  listener:loop()
end)
