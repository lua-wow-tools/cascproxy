local args = (function()
  local parser = require('argparse')()
  parser:option('-b --build', 'build(s) to serve'):count('*')
  parser:option('-c --cache', 'cache directory', 'cache')
  parser:option('-p --port', 'web server port', '8080'):convert(tonumber)
  parser:option('-t --product', 'product(s) to serve'):count('*'):choices({
    'wow',
    'wowt',
    'wow_classic',
    'wow_classic_beta',
    'wow_classic_era',
    'wow_classic_era_ptr',
    'wow_classic_ptr',
  })
  return parser:parse()
end)()

local log = print

-- Tune GC very tightly. CASCs are memory hogs.
collectgarbage('setpause', 100)
collectgarbage('setstepmul', 500)

require('lfs').mkdir(args.cache)

local bcascs, pcascs = (function()
  local casc = require('casc')
  local bcascs = {}
  local pcascs = {}
  local root = 'http://us.patch.battle.net:1119/'
  do
    local _, cdn, ckey = casc.cdnbuild(root .. 'wow', 'us')
    for _, build in ipairs(args.build) do
      log('loading', build)
      local handle, err = casc.open({
        bkey = build,
        cache = args.cache,
        cacheFiles = true,
        cdn = cdn,
        ckey = ckey,
        locale = casc.locale.US,
        log = log,
        zerofillEncryptedChunks = true,
      })
      if not handle then
        print('unable to open ' .. build .. ': ' .. err)
        os.exit()
      end
      bcascs[build] = handle
    end
  end
  for _, product in ipairs(args.product) do
    local bkey, cdn, ckey, version = casc.cdnbuild(root .. product, 'us')
    if not bkey then
      print('unable to open ' .. product .. ': cannot get version')
      os.exit()
    end
    log('loading', product, version)
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
    pcascs[product] = handle
  end
  return bcascs, pcascs
end)()

local pathparser = (function()
  local lpeg = require('lpeg')
  local C, P, R = lpeg.C, lpeg.P, lpeg.R
  local ty = C(P('product') + P('build'))
  local fdid = P('/fdid/') * C(R('09') ^ 1) / tonumber
  local name = P('/name/') * C(R('az', 'AZ', '09', '__', '--', '//', '..') ^ 1)
  return P('/') * ty * P('/') * C(R('az', 'AZ', '09', '__') ^ 1) * (fdid + name) * P(-1)
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
    local path = req:get(':path')
    local ty, name, fid = pathparser:match(path)
    local casc = (ty == 'build' and bcascs or pcascs)[name]
    local res = mkres()
    if not casc or not fid then
      res:append(':status', '400')
      assert(stream:write_headers(res, true))
      log('400', path)
      return
    end
    local data = casc:readFile(fid)
    if not data then
      res:append(':status', '404')
      assert(stream:write_headers(res, true))
      log('404', path)
      return
    end
    res:append(':status', '200')
    assert(stream:write_headers(res, false))
    assert(stream:write_chunk(data, true))
    log('200', path)
  end,
  port = args.port,
}))
log('HTTP server ready')
pcall(function()
  listener:loop()
end)
