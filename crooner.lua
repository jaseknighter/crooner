-- crooner
-- 0.1 @jaseknighter
-- llllllll.co/t/<insert link>
--
-- tune and play non-1v/oct synths with crow
--
-- based on @markeats' tuner
-- E3 : Reference note
--

-- this version uses norns built in pitch polls

local ControlSpec = require "controlspec"
local MusicUtil = require "musicutil"
local Formatters = require "formatters"

engine.name = "TestSine"

local REFRESH_RATE = 15
local TUNE_RATE = 100
local screen_dirty = true

local current_freq = -1
local current_fpc_freq = -1
local current_fpc_conf = -1
local last_freq = -1
local close_voltage = -5
local in1v=0
tuning=false
local test_voltage= -5
local last_test_voltage = -5

-- Encoder input
function enc(n, delta)
  
  if n == 2 then
          
  elseif n == 3 then
    params:delta("note_vol", delta)
  end
end

-- Key input
function key(n, z)
  if z == 1 then
    if n == 2 then
      
    elseif n == 3 then
      
    end
  end
end


local function update_freq(freq)
  current_freq = freq
  if current_freq > 0 then last_freq = current_freq end
  screen_dirty = true
end

local function round_decimals (value_to_round, num_decimals, rounding_direction)
  local rounded_val
  local mult = 10^num_decimals
  if rounding_direction == "up" then
    rounded_val = math.floor(value_to_round * mult + 0.5) / mult
  else
    rounded_val = math.floor(value_to_round * mult + 0.5) / mult
  end
  return rounded_val
end



function start_tuner()
  osc.send( { "localhost", 57120 }, "/sc_crooner/start_tuner")
end

function stop_tuner()
  osc.send( { "localhost", 57120 }, "/sc_crooner/stop_tuner")
end

function init()
  print("init sc")
  osc.send( { "localhost", 57120 }, "/sc_crooner/init")
  -- osc.send( { "localhost", 57120 }, "/sc_crooner/get_freq_conf")
  --crow.clear()
  engine.amp(0)
  
  
  
  -- crow.input[1].mode('stream',0.01)
  -- -- crow.input[1].stream = function(v) end
  -- -- crow.input[1].stream = function(v) print("volts: "..v) crow.output[1].volts=v end
  -- crow.input[1].stream = function(v) 
  --   crow.output[1].volts=v 
  --   in1v=v
  -- end
  
  -- Add params
  
  params:add{type = "option", id = "in_channel", name = "In Channel", options = {"Left", "Right"}}
  
  params:add{type = "option", id = "note", name = "Note", options = MusicUtil.NOTE_NAMES, default = 10, action = function(value)
    engine.hz(MusicUtil.note_num_to_freq(59 + value))
    screen_dirty = true
  end}
  params:add{type = "control", id = "note_vol", name = "Note Volume", controlspec = ControlSpec.UNIPOLAR, action = function(value)
    engine.amp(value)
    screen_dirty = true
  end}
  
  params:bang()
  
  -- Polls
  
  pitch_poll_l = poll.set("pitch_in_l", function(value)
    if params:get("in_channel") == 1 then
      -- update_freq(value)
    end
  end)
  pitch_poll_l:start()
  
  pitch_poll_r = poll.set("pitch_in_r", function(value)
    if params:get("in_channel") == 2 then
      -- update_freq(value)
    end
  end)
  pitch_poll_r:start()

  -- local tune_refresh_metro = metro.init()
  -- tune_refresh_metro.event = function()
  --   tune()
  -- end
  
  -- tune_refresh_metro:start(1 / TUNE_RATE)

  
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  
  screen_refresh_metro:start(1 / REFRESH_RATE)
  screen.aa(1)
end

-- note_nums = {45,47,48,52,55,64,72}
-- note_nums = {48,52,55,64,72}
note_nums = {49, 52,55,64,67}
voltages = {}
local found_times=0
local voltage_over_times=0

--------------------------
-- osc functions
--------------------------
function osc.event(path,args,from)
  -- print("osc event", path,args,from)
  if path == "/lua_crooner/sc_inited" then
    print("sc inited")
    osc.send( { "localhost", 57120 }, "/sc_crooner/start_metadata_collection")
  elseif path == "/lua_crooner/pitch_confidence" then
    -- params:set("x_axis",args[1])
    update_freq(args[1])
    current_fpc_freq=args[1]
    current_fpc_conf=args[2]
    -- print("pitch/confidence: ", args[1],args[2])
    -- tab.print(args)
  elseif path == "/lua_crooner/set_crow_voltage" then
    local output = tonumber(args[1])
    local volts = args[2]
    test_voltage = volts
    crow.output[output].volts = volts
  end
end

function tune()
  -------------------
  
  -------------------
end

function tune_crow(start_voltage)
  crow.clear()
  start_tuner()
  clock.sleep(1)
  start_voltage = start_voltage or -5
  test_voltage = start_voltage
  for i=1,#note_nums do
    local target_freq = MusicUtil.note_num_to_freq (note_nums[i])
    print("start tune #",i,target_freq)
    tuning=true
    while tuning==true do
      crow.output[1].volts=test_voltage
      if params:get("in_channel") == 1 then
        pitch_poll_l:update()
        
      else
        pitch_poll_r:update()
      end
  
      if (current_freq > target_freq-1 and current_freq < target_freq+1) then
        -- if current_freq > target_freq-0.1 and current_freq < target_freq+0.5 or found_times > 300 then
        if current_freq > target_freq-0.1 and current_freq < target_freq+0.5 and current_fpc_conf > 5 then
          print("found target voltage", target_freq, current_freq, test_voltage)
          print("flucoma", current_fpc_freq, current_fpc_conf)
          tuning=false
          found_times=0
          voltage_over_times=0
          voltages[i] = test_voltage
        else
          if found_times<2 then print("close to target voltage", target_freq, test_voltage, current_freq, found_times) end
          found_times=found_times+1
          close_voltage = test_voltage
          test_voltage=test_voltage+0.0001
          -- last_test_voltage = test_voltage
          -- crow.output[1].volts=test_voltage
          clock.sleep(0.05)
        end
      -- elseif test_voltage > 5  then
      --   print("couldn't find frequency :(", target_freq, found_times)
      --   tuning=false
      --   found_times=0
      --   voltage_over_times=0
      elseif (current_freq > target_freq+1 and test_voltage > start_voltage + 0.01) then 
        if found_times > 0 and (voltage_over_times > 10  or current_fpc_conf > 5) then
          print("mostly found target voltage", target_freq, current_freq, last_test_voltage, test_voltage)
          print("flucoma", current_fpc_freq, current_fpc_conf)
          tuning=false
          found_times=0
          voltage_over_times=0
          voltages[i] = close_voltage
          -- voltages[i] = last_test_voltage
        elseif voltage_over_times < 2000 then
          voltage_over_times=voltage_over_times+1
          test_voltage=test_voltage+0.0001
          last_test_voltage = test_voltage
          -- crow.output[1].volts=test_voltage
          -- last_test_voltage = test_voltage
          -- print("voltage over", target_freq, current_freq, test_voltage, voltage_over_times)
          -- print("flucoma", current_fpc_freq, current_fpc_conf)
          clock.sleep(0.01)
        else
          print("couldn't find target voltage, skipping", target_freq, test_voltage, current_freq, found_times)
          tuning=false
          found_times=0
          voltage_over_times=0
        end
      else
        -- print("test_voltage/current_freq",test_voltage,current_freq)
        -- crow.output[1].volts=test_voltage
        -- last_test_voltage = test_voltage
        if current_freq < target_freq-30 and voltage_over_times==0 then
          test_voltage=test_voltage+0.001
          clock.sleep(0.005)
        elseif current_freq < target_freq-10 and voltage_over_times==0 then
          test_voltage=test_voltage+0.001
          clock.sleep(0.01)
        else
          test_voltage=current_freq>130 and test_voltage+0.0005 or test_voltage+0.0001
          clock.sleep(0.01)
        end  
        if current_freq < target_freq and voltage_over_times > 10 then
          voltage_over_times = 0
        end
      end
      last_test_voltage = test_voltage
    end
  end
end

function redraw()
  screen.clear()
  
  -- Draw rules
  
  for i = 1, 11 do
    local x = util.round(12.7 * (i - 1)) + 0.5
    if i == 6 then
      if current_freq > 0 then screen.level(15)
      else screen.level(3) end
      screen.move(x, 24)
      screen.line(x, 35)
    else
      if current_freq > 0 then screen.level(3)
      else screen.level(1) end
      screen.move(x, 29)
      screen.line(x, 35)
    end
    screen.stroke()
  end
  
  -- Draw last freq line
  
  note_num = MusicUtil.freq_to_note_num(last_freq)
  local freq_x
  if last_freq > 0 then
    freq_x = util.explin(math.max(MusicUtil.note_num_to_freq(note_num - 1), 0.00001), MusicUtil.note_num_to_freq(note_num + 1), 0, 128, last_freq)
    freq_x = util.round(freq_x) + 0.5
  else
    freq_x = 64.5
  end
  if current_freq > 0 then screen.level(15)
  else screen.level(3) end
  screen.move(freq_x, 29)
  screen.line(freq_x, 40)
  screen.stroke()
  
  -- Draw text
  
  screen.move(64, 19)
  if current_freq > 0 then screen.level(15)
  else screen.level(3) end
  
  if last_freq > 0 then
    screen.text_center(MusicUtil.note_num_to_name(note_num, true) .. " " ..note_num)
  end
  
  if last_freq > 0 then
    screen.move(64, 50)
    if current_freq > 0 then 
      screen.level(3)
    else screen.level(1) end
    screen.text_center(Formatters.format_freq_raw(last_freq) .. " / " .. round_decimals(test_voltage,4) .."v")
  end
  

  -- Draw ref note
  
  screen.move(128, 8)
  screen.level(util.round(params:get("note_vol") * 15))
  screen.text_right(params:string("note"))
  
  screen.fill()
  
  screen.update()
end


function cleanup ()
  stop_tuner()
end