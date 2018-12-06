_addon.name = 'EraMobDrops'
_addon.author = 'DiscipleOfEris'
_addon.version = '1.2.0'
_addon.commands = {'mobdrops', 'drops'}

config = require('config')
texts = require('texts')
require('tables')
require('strings')
res = require('resources')
require('sqlite3')

defaults = {}
defaults.header = "${name} (Lv.${lvl}, Respawn: ${respawn})"
defaults.subheader = "TH: ${TH}"
defaults.footer = ""
defaults.noDrops = "No Drops"
defaults.Steal = "${item.name}"
defaults.display = {}
defaults.display.pos = {}
defaults.display.pos.x = 0
defaults.display.pos.y = 0
defaults.display.bg = {}
defaults.display.bg.red = 0
defaults.display.bg.green = 0
defaults.display.bg.blue = 0
defaults.display.bg.alpha = 102
defaults.display.text = {}
defaults.display.text.font = 'Consolas'
defaults.display.text.red = 255
defaults.display.text.green = 255
defaults.display.text.blue = 255
defaults.display.text.alpha = 255
defaults.display.text.size = 12

settings = config.load(defaults)

box = texts.new("", settings.display, settings)

zones = res.zones
items = res.items

local mobKeys = {'mob_id', 'name', 'zone_id', 'drop_id', 'respawn', 'lvl_min', 'lvl_max'}
local dropKeys = {'drop_id', 'drop_type', 'item_id', 'item_rate'}

DROP_TYPE = { NORMAL=0x0, GROUPED=0x1, STEAL=0x2, DESPOIL=0x4 }

TH_lvl = 0
prev_TH_lvl = 0
prevMouse = {x=-1,y=-1}
CLICK_DISTANCE = 2.0^2

prev_target_id = -1

windower.register_event('load',function()
  db = sqlite3.open(windower.addon_path..'/mobs_drops.db', sqlite3.OPEN_READONLY)
  
  if not windower.ffxi.get_info().logged_in then return end
  
  local player = windower.ffxi.get_player()
  local target = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t') or player
  local info = getTargetInfo(target)

  updateInfo(info)
end)

windower.register_event('unload', function()
  db:close()
end)

windower.register_event('mouse', function(type, x, y, delta, blocked)
  if not box:hover(x,y) or type == 0 then return end

  mouse = {x=x,y=y}
  clicked = false
  
  --windower.add_to_chat(0, tostring(type)..': '..x..','..y..' delta: '..delta..' blocked: '..tostring(blocked))
  
  if type == 1 then
    prevMouse = mouse
  elseif type == 2 and distanceSquared(mouse, prevMouse) < CLICK_DISTANCE then
    -- left clicked
    TH_lvl = TH_lvl + 1
    clicked = true
  elseif type == 4 then
    prevMouse = mouse
  elseif type == 5 and distanceSquared(mouse, prevMouse) < CLICK_DISTANCE then
    -- right clicked
    TH_lvl = TH_lvl - 1
    clicked = true
  elseif type == 7 then
    prevMouse = mouse
  elseif type == 8 and distanceSquared(mouse, prevMouse) < CLICK_DISTANCE then
    -- middle clicked
    TH_lvl = TH_lvl - 1
    clicked = true
  elseif delta > 0 then
    -- scrolled up
  elseif delta < 0 then
    -- scrolled down
  end
  
  if TH_lvl < 0 then TH_lvl = 0 end
  if TH_lvl > 10 then TH_lvl = 10 end
  
  return true
end)

windower.register_event('prerender', function()
  local player = windower.ffxi.get_player()
  local target = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t') or player

  if ((target and target.id) or -1) == prev_target_id and TH_lvl == prev_TH_lvl then return end
  prev_target_id = (target and target.id) or -1
  prev_TH_lvl = TH_lvl
  
  local info = getTargetInfo(target)
  updateInfo(info)
end)

windower.register_event('addon command', function(command, ...)
  args = L{...}
  
  if command == "item" then
    name = strip(args:concat(' '))
    item = items:with('en', function(val)
      if name == strip(val) then
        return true
      end
    end)
    
    if item == nil then
      windower.add_to_chat(0, 'Could not find an item with the name: '..name)
      return
    end
    
    windower.add_to_chat(0, 'Searching for mobs that drop: '..item.en)
    
    drops = dbGetDropsWithItem(item.id)
    drop_ids = T{}
    mobsProcessed = T{}
    for _, drop in pairs(drops) do drop_ids:insert(drop.drop_id) end
    mobs = dbGetMobsWithDrops(drop_ids)
    for _, mob in pairs(mobs) do
      tmp = {}
      for _, drop in pairs(drops) do
        if mob.drop_id == drop.drop_id then table.insert(tmp, string.format('%.1f%%', drop.item_rate/10)) end
      end
      mob.drops = table.concat(tmp, ', ')
      
      found = false
      for _, row in pairs(mobsProcessed) do
        if row.zone_id == mob.zone_id and row.name == mob.name and row.drops == mob.drops then
          found = true
          row.count = row.count + 1
          break
        end
      end
      if not found then
        mobsProcessed:insert({zone_id=mob.zone_id, name=mob.name, drops=mob.drops, count=1})
      end
    end
    
    table.sort(mobsProcessed, function(a, b)
      return a.zone_id < b.zone_id
    end)
    
    for _, mob in pairs(mobsProcessed) do
      windower.add_to_chat(0, ''..zones[mob.zone_id].en..': '..mob.count..' '..mob.name..': '..mob.drops)
    end
  end
end)

function getTargetInfo(target)
  local info = {}

  if target == nil then return {type='none'} end
  
  if target.spawn_type == 16 then
    local zone_id = windower.ffxi.get_info().zone
    local mob, drops = getMobInfo(target, zone_id)
    
    info.type = 'mob'
    info.mob = mob
    info.drops = drops
  end
  
  return info
end

function getMobInfo(target, zone_id)
  if not db:isopen() then return end
  
  local mob = false
  local drops = {}
  
  local idQuery = 'SELECT * FROM mobs WHERE mob_id='..target.id..''
  for mobRow in db:rows(idQuery) do
    mob = kvZip(mobKeys, mobRow)
    drops = dbGetDrops(mob.drop_id)
  end
  
  return mob, drops
end

function updateInfo(info)
  if info.type ~= 'mob' then
    prev_target_id = 0
    box:text('')
    box:visible(false)
    return
  end
  
  local steal = ''
  local lines = {}
  local drops = info and info.drops or {}
  for _, drop in pairs(drops) do
    if testflag(drop.drop_type, DROP_TYPE.STEAL) then
      steal = steal..'Steal: '..items[drop.item_id].en..'\n'
    elseif testflag(drop.drop_type, DROP_TYPE.GROUPED) then
      rate = calculateGroupedRate(drop, drops)
      table.insert(lines, '1: '..items[drop.item_id].en..string.format(': %.1f%%', rate/10))
    else
      rate = applyTH(drop.item_rate)
      table.insert(lines, items[drop.item_id].en..string.format(': %.1f%%', rate/10))
    end
  end
  
  local str = ""
  
  if #steal > 0 or #lines > 0 then
    if #settings.header > 0 then str = settings.header..'\n' end
    if #settings.subheader > 0 then str = str..settings.subheader..'\n' end
    str = str..steal..table.concat(lines, '\n')
    if #settings.footer > 0 then str = str..'\n'..settings.footer end
  else
    str = settings.noDrops
  end
  
  box:text(str)
  
  lvl = tostring(info.mob.lvl_min)
  if info.mob.lvl_max ~= info.mob.lvl_min then lvl = lvl..'-'..tostring(info.mob.lvl_max) end
  update = table.update({TH=TH_lvl, lvl=lvl}, info.mob)
  update.respawn = update.respawn / 60
  if update.respawn > 60 then
    update.respawn = string.format('%.1fh', update.respawn/60)
  else
    update.respawn = string.format('%.1fm', update.respawn)
  end
  
  box:update(update)
  box:visible(true)
end

function dbGetDrops(drop_id)
  local query = 'SELECT * FROM drops WHERE drop_id='..drop_id
  drops = {}
  for row in db:rows(query) do
    table.insert(drops, kvZip(dropKeys, row))
  end
  
  return drops
end

function dbGetDropsWithItem(item_id)
  local query = 'SELECT * FROM drops WHERE item_id='..item_id
  drops = {}
  for row in db:rows(query) do
    table.insert(drops, kvZip(dropKeys, row))
  end
  
  return drops
end

function dbGetMobsWithDrops(drop_ids)
  local query = 'SELECT * FROM mobs WHERE drop_id IN ('..table.concat(drop_ids, ',')..')'
  mobs = {}
  for row in db:rows(query) do
    table.insert(mobs, kvZip(mobKeys, row))
  end
  
  return mobs
end

function applyTH(item_rate)
  rate = item_rate/1000
  
  if TH_lvl > 2 then
    rate = rate + (TH_lvl-2)*0.01
  end
  
  if TH_lvl > 1 then
    rate = 1-(1-rate)^3
  elseif TH_lvl > 0 then
    rate = 1-(1-rate)^2
  end
  
  return math.min(math.floor(rate*1000),1000)
end

function calculateGroupedRate(drop, drops)
  totalRate = 0
  for i, drop2 in pairs(drops) do
    if testflag(drop2.drop_type, DROP_TYPE.GROUPED) then
      totalRate = totalRate + drop2.item_rate
    end
  end
  
  return drop.item_rate / totalRate * 1000
end

function values(t, keys)
  list = {}
  
  if type(keys) == 'table' then
    for i=1, #keys do
      table.insert(list, t[keys[i]])
    end
  else
    for k, v in pairs(t) do
      table.insert(list, v)
    end
  end
  
  return list
end

function testflag(set, flag)
  return set % (2*flag) >= flag
end

-- Return an associative array that takes two lists and uses the first for its keys and the second for its values.
function kvZip(keys, values)
  len = math.min(#keys, #values)
  t = {}
  
  for i=1, len do
    t[keys[i]] = values[i]
  end
  
  return t
end

function distanceSquared(A, B)
  return (A.x - B.x)^2 + (A.y - B.y)^2
end

function strip(str)
  return str:lower():gsub(' ', ''):gsub('-', ''):gsub('%.', ''):gsub('\'','')
end