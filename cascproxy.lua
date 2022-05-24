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

assert(casc) -- TODO actually use

local mkres = require('http.headers').new
assert(require('http.server').listen({
  host = 'localhost',
  onerror = function(_, ctx, op, err)
    local msg = op .. ' on ' .. tostring(ctx) .. ' failed'
    if err then
      msg = msg .. ': ' .. tostring(err)
    end
    assert(io.stderr:write(msg, '\n'))
  end,
  onstream = function(_, stream)
    assert(stream:get_headers())
    local res = mkres()
    res:append(':status', '200')
    res:append('content-type', 'text/plain')
    assert(stream:write_headers(res, false))
    assert(stream:write_chunk('Hello, world!', true))
  end,
  port = args.port,
})):loop()
