--
-- [boundary.com] Couchbase Lua Plugin
-- [author] Valeriu Paloş <me@vpalos.com>
--

--
-- Imports.
--
local fs    = require('fs')
local json  = require('json')
local http  = require('http')
local os    = require('os')
local sha1  = require('sha1')
local timer = require('timer')
local tools = require('tools')
local url   = require('url')

--
-- Initialize.
--
local _buckets          = {}
local _parameters       = json.parse(fs.readFileSync('param.json')) or {}

local _serverHost       = _parameters.serverHost or 'localhost'
local _serverPort       = _parameters.serverPort or 8080

local _apiKey           = _parameters.apiKey or error("API Key must be provided (see CloudStack UI)!")
local _secretKey        = _parameters.secretKey or error("Secret Key must be provided (see CloudStack UI)!")

local _pollRetryCount   = tools.fence(tonumber(_parameters.pollRetryCount) or    3,   0, 1000)
local _pollRetryDelay   = tools.fence(tonumber(_parameters.pollRetryDelay) or 3000,   0, 1000 * 60 * 60)
local _pollInterval     = tools.fence(tonumber(_parameters.pollInterval)   or 5000, 100, 1000 * 60 * 60 * 24)
local _advancedMetrics  = _parameters.advancedMetrics == true

--
-- Metrics source.
--
local _source =
  (type(_parameters.source) == 'string' and _parameters.source:gsub('%s+', '') ~= '' and _parameters.source) or
   os.hostname()

--
-- Compile a signed query string in CLoudStack-style from a given set of parameters.
--
function compileUri(parameters)

  -- Inject fundamentals.
  parameters['response'] = 'json'
  parameters['apiKey'] = _apiKey

  -- Compute query string.
  local tuples = {}
  for key, value in pairs(parameters) do
    table.insert(tuples, tools.urlEncode(key) .. "=" .. tools.urlEncode(value))
  end
  local query = table.concat(tuples, '&')

  -- Compile signature.
  table.sort(tuples)
  local text = table.concat(tuples, '&'):lower()
  local signature = tools.urlEncode(tools.base64(sha1.hmac_binary(_secretKey, text)))

  -- Assemble.
  local uri = string.format('http://%s:%s/client/api?%s&signature=%s', _serverHost, _serverPort, query, signature)
  -- print(uri)
  return uri
end

--
-- Get a JSON data set from the server at the given URL (includes query string).
--
function list(parameters, callback)
  local remaining = _pollRetryCount
  local options = url.parse(compileUri(parameters))

  -- Make sure connection is not dropped.
  options['headers'] = {
    ['Connection'] = 'keep-alive'
  }

  -- Process data.
  function handler(response)
    local data = {}

    response:once('error', retry)

    response:on('data', function(chunk)
      table.insert(data, chunk)
    end)

    response:on('end', function()
      local success, data = pcall(json.parse, table.concat(data))
      local failure = "Unable to parse response!"
      local command = parameters['command']:lower()

      if success then
        local responseField = command .. "response"

        if data[responseField] then
          data = data[responseField]
          failure = data['errorcode'] and data['errortext']
        elseif data['errorresponse'] then
          failure = data['errorresponse']['errortext']
        end
      end

      if failure then
        retry("ERROR: " .. failure)
      else
        local section = command:match('^list(%w+)s$')
        if section then
          data = data[section] or data[section .. 's'] or data
        end

        callback(data)
      end

      response:destroy()
    end)
  end

  function retry(result)
    if remaining > 0 then
      remaining = remaining - 1
    end
    if remaining == 0 then
      error(tostring(result.message or result))
    end

    timer.setTimeout(_pollRetryDelay, perform)
  end

  function perform()
    local request = http.request(options, handler)
    request:once('error', retry)
    request:done()
  end

  perform()
end

--
-- Retrieve data in paginated queries.
--
function listPaginated(parameters, callback)
  local page
  local page = 0
  local size = 500
  local items = {}

  -- Next page.
  function advance()
    page = page + 1
    parameters['page'] = page
    parameters['pagesize'] = size

    -- Raw call.
    list(parameters, function(data)
      for _, item in ipairs(data) do
        table.insert(items, item)
      end

      if #data == size then
        process.nextTick(advance())
      else
        callback(items)
      end
    end)
  end

  advance()
end

--
-- Schedule poll.
--
function schedule()
  timer.setTimeout(_pollInterval, poll)
end

--
-- Parse numeric metric value.
--
function parse(value)
  if type(value) ~= 'number' then
    value = tonumber((tostring(value):match('([%d%.]+)'))) or 0
  end
  return value
end

--
-- Metric aggregation functions.
--
function sum(items)
  local result = 0
  for _, item in ipairs(items) do
    result = result + parse(item)
  end
  return result
end

function avg(items)
  local result = 0
  for _, item in ipairs(items) do
    result = result + parse(item)
  end
  return result / #items
end

function min(items)
  local result = parse(items[1])
  for _, item in ipairs(items) do
    local value = parse(item)
    if result > value then
      result = value
    end
  end
  return result
end

function max(items)
  local result = parse(items[1])
  for _, item in ipairs(items) do
    local value = parse(item)
    if result < value then
      result = value
    end
  end
  return result
end

function cnt(items)
  return #items
end

--
-- Create a new aggregator function that only aggregates filtered values.
--
function filter(value, aggregator)
  return function(items)
    local filtered = {}
    for _, item in ipairs(items) do
      if item == value then
        table.insert(filtered, item)
      end
    end
    return aggregator(filtered)
  end
end

--
-- Produce a function that extrcts a capacity field of given kind.
--
function capacity(kind, field)
  -- 0* = CAPACITY_TYPE_MEMORY
  -- 1* = CAPACITY_TYPE_CPU
  -- 2* = CAPACITY_TYPE_STORAGE
  -- 3* = CAPACITY_TYPE_STORAGE_ALLOCATED
  -- 4* = CAPACITY_TYPE_VIRTUAL_NETWORK_PUBLIC_IP
  -- 5* = CAPACITY_TYPE_PRIVATE_IP
  -- 6* = CAPACITY_TYPE_SECONDARY_STORAGE
  -- 7* = CAPACITY_TYPE_VLAN
  -- 8* = CAPACITY_TYPE_DIRECT_ATTACHED_PUBLIC_IP
  -- 9. = CAPACITY_TYPE_LOCAL_STORAGE
  return function(set)
    for _, subset in ipairs(set['capacity']) do
      if subset['type'] == kind then
        return subset[field]
      end
    end
  end
end

--
-- Metrics reference table.
--
local DEFINITIONS = {

  -- Zones.
  {
    request = {
      ['command'] = 'listZones',
      ['showcapacities'] = 'true'
    },
    standard = {
      groupBy = {
        'name'
      },
      metrics = {
        ['CLOUDSTACK_MEMORY_TOTAL']                     = { field = capacity(0, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_MEMORY_USED']                      = { field = capacity(0, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_CPU_TOTAL']                        = { field = capacity(1, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_CPU_USED']                         = { field = capacity(1, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_STORAGE_TOTAL']                    = { field = capacity(2, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_STORAGE_USED']                     = { field = capacity(2, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_STORAGE_ALLOCATED_TOTAL']          = { field = capacity(3, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_STORAGE_ALLOCATED_USED']           = { field = capacity(3, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_VIRTUAL_NETWORK_PUBLIC_IP_TOTAL']  = { field = capacity(4, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_VIRTUAL_NETWORK_PUBLIC_IP_USED']   = { field = capacity(4, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_PRIVATE_IP_TOTAL']                 = { field = capacity(5, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_PRIVATE_IP_USED']                  = { field = capacity(5, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_SECONDARY_STORAGE_TOTAL']          = { field = capacity(6, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_SECONDARY_STORAGE_USED']           = { field = capacity(6, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_VLAN_TOTAL']                       = { field = capacity(7, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_VLAN_USED']                        = { field = capacity(7, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_DIRECT_ATTACHED_PUBLIC_IP_TOTAL']  = { field = capacity(8, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_DIRECT_ATTACHED_PUBLIC_IP_USED']   = { field = capacity(8, 'capacityused'),  apply = sum },
        ['CLOUDSTACK_LOCAL_STORAGE_TOTAL']              = { field = capacity(9, 'capacitytotal'), apply = sum },
        ['CLOUDSTACK_LOCAL_STORAGE_USED']               = { field = capacity(9, 'capacityused'),  apply = sum },
      }
    }
  },

  -- Viewer sessions.
  {
    request = {
      ['command'] = 'listSystemVms',
      ['systemvmtype'] = 'consoleproxy'
    },
    standard = {
      groupBy = {
        'zonename'
      },
      metrics = {
        ['CLOUDSTACK_ACTIVE_VIEWER_SESSIONS']           = { field = 'activeviewersessions', apply = sum }
      }
    },
    advanced = {
      groupBy = {
        'zonename',
        'name'
      }
    }
  },

  -- Events.
  {
    request = {
      ['command'] = 'listEvents',
      ['listall'] = 'true'
    },
    standard = {
      metrics = {
        ['CLOUDSTACK_EVENTS_INFO']                      = { field = 'level', apply = filter('INFO',  cnt) },
        ['CLOUDSTACK_EVENTS_WARN']                      = { field = 'level', apply = filter('WARN',  cnt) },
        ['CLOUDSTACK_EVENTS_ERROR']                     = { field = 'level', apply = filter('ERROR', cnt) },
      }
    }
  },

  -- Alerts.
  {
    request = {
      ['command'] = 'listAlerts'
    },
    standard = {
      metrics = {
        ['CLOUDSTACK_ALERTS']                           = { field = 'type', apply = cnt },
        ['CLOUDSTACK_ALERTS_MEMORY']                    = { field = 'type', apply = filter(0, cnt) },
        ['CLOUDSTACK_ALERTS_CPU']                       = { field = 'type', apply = filter(1, cnt) },
        ['CLOUDSTACK_ALERTS_STORAGE']                   = { field = 'type', apply = filter(2, cnt) },
      }
    }
  },

  -- Accounts.
  {
    request = {
      ['command'] = 'listAccounts',
      ['listall'] = 'true'
    },
    standard = {
      metrics = {
        ['CLOUDSTACK_ACCOUNTS_TOTAL']                   = { field = 'state', apply = cnt },
        ['CLOUDSTACK_ACCOUNTS_ENABLED']                 = { field = 'state', apply = filter('enabled',  cnt) },
      }
    }
  }
}

--
-- Print a metric.
--
function metric(stamp, id, value, source)
  if (type(source) == 'table') then
    source = table.concat(source, '.'):gsub('%s+', '-')
  end
  print(string.format('%s %s %s %d', id, value, (source and source ~= '') or _source, stamp))
end

--
-- Extract fields from metrics sets as a flat array.
--
function extract(set, rule)
  local result
  local kind = type(rule.field)

  if kind == 'string' then
    result = set[rule.field] or rule.default or 0
  elseif kind == 'function' then
    result = rule.field(set) or rule.default or 0
  end

  return result
end

--
-- Extract, aggregate and compile metrics.
--
function produceMetrics(stamp, entries, groupBy, definitions)
  local metrics = {}

  -- Walk entries.
  for _, entry in ipairs(entries) do

    -- Compile group name.
    local group = {}
    for _, label in ipairs(groupBy or {}) do
      if entry[label] then
        table.insert(group, entry[label])
      end
    end
    group = table.concat(group, '.'):gsub('%s+', '-')

    -- Extract.
    metrics[group] = metrics[group] or {}
    for name, rule in pairs(definitions) do
      metrics[group][name] = metrics[group][name] or {}
      table.insert(metrics[group][name], extract(entry, rule))
    end
  end

  -- Aggregate.
  for group, sets in pairs(metrics) do
    for name, rule in pairs(definitions) do
      metrics[group][name] = rule.apply(metrics[group][name])
    end
  end

  -- Sort groups.
  local groups = {}
  for group, _ in pairs(metrics) do
    table.insert(groups, group)
  end
  table.sort(groups)

  -- Publish.
  for _, group in pairs(groups) do
    for name, value in pairs(metrics[group]) do
      metric(stamp, name, value, group)
    end
  end
end

--
-- Produce metrics.
--
function poll()
  local stamp = os.time()

  -- Reschedule poll after all requests have completed.
  local remaining = 0
  function request(options, callback)
    remaining = remaining + 1
    listPaginated(options, function(data)
      callback(data)
      remaining = remaining - 1
      if remaining == 0 then
        schedule()
      end
    end)
  end

  -- Process metrics definitions.
  for _, definition in ipairs(DEFINITIONS) do
    request(definition.request, function(data)

      produceMetrics(
        stamp,
        data,
        definition.standard.groupBy,
        definition.standard.metrics)

      if _advancedMetrics and definition.advanced then
        produceMetrics(
          stamp,
          data,
          definition.advanced.groupBy or definition.standard.groupBy,
          definition.advanced.metrics or definition.standard.metrics)
      end

    end)
  end

end

-- Trigger polling.
poll()