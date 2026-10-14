-- 单按 Shift 上屏原始编码；在候选菜单中按 Shift+Space，上屏当前中文候选的英文映射。

local cn_en_mapping = require("cn_en_mapping")
local custom_english = require("custom_english")

local M = {}
local kAccepted = 1
local kNoop = 2
local shift_l_keycode = KeyEvent("Shift_L").keycode
local shift_r_keycode = KeyEvent("Shift_R").keycode
local return_keycode = KeyEvent("Return").keycode

-- 初始化英文上屏快捷键并设置共享分片缓存容量。
function M.init(env)
    local config = env.engine.schema.config
    local name_space = env.name_space:gsub("^%*", "")

    env.enable = config:get_bool(name_space .. "/enable")
    if env.enable == nil then
        env.enable = true
    end

    env.commit_english_key = config:get_string(name_space .. "/commit_english_key") or "Shift+space"
    env.custom_english_key = config:get_string(name_space .. "/custom_english_key") or "Control+Return"
    cn_en_mapping.configure(config:get_int("cn_en_translation/cache_size"))
    env.mapping = cn_en_mapping.mapping
    env.shift_pending = nil
end

-- 查询当前候选显示文本或原始文本的英文翻译。
local function find_translation(cand, mapping)
    local genuine = cand:get_genuine()
    if genuine and genuine.text ~= cand.text then
        local english = mapping[genuine.text]
        if english then
            return english
        end
    end
    return mapping[cand.text]
end

-- 判断当前按键是否为左右 Shift。
local function is_shift_key(key)
    return key.keycode == shift_l_keycode or key.keycode == shift_r_keycode
end

-- 处理单按 Shift 上屏原始编码。
local function handle_shift_commit(key, env, context)
    if is_shift_key(key) then
        if key:release() then
            local should_consume = env.shift_pending ~= nil
            local should_commit = env.shift_pending == "waiting"
            env.shift_pending = nil

            if should_commit then
                local input = context.input or ""
                if input ~= "" then
                    env.engine:commit_text(input)
                    context:clear()
                end
            end
            return should_consume and kAccepted or kNoop
        end

        local input = context.input or ""
        if input ~= "" and not context:get_option("ascii_mode") then
            env.shift_pending = "waiting"
            return kAccepted
        else
            env.shift_pending = nil
        end
        return kNoop
    end

    if env.shift_pending == "waiting" and not key:release() then
        env.shift_pending = "used"
    end
    return nil
end

-- 处理 Shift 原始编码、英文映射上屏和 Ctrl+Return 英文收词。
function M.func(key, env)
    local engine = env.engine
    local context = engine.context
    local shift_result = handle_shift_commit(key, env, context)
    if shift_result ~= nil then
        return shift_result
    end

    if key:release() then
        return kNoop
    end

    local input = context.input or ""
    if not context:get_option("ascii_mode") and (key:repr() == env.custom_english_key or (key.keycode == return_keycode and key:ctrl())) and input:match("^[A-Za-z]+$") then
        if custom_english.add(input) then
            engine:commit_text(input)
            context:clear()
        else
            local composition = context.composition
            if not composition:empty() then
                composition:back().prompt = "收词失败，请检查 custom_english.txt 写入权限"
            end
            log.error("无法写入英文个人词库 custom_english.txt")
        end
        return kAccepted
    end

    if not env.enable or key:repr() ~= env.commit_english_key then
        return kNoop
    end

    if not context:has_menu() then
        return kNoop
    end

    local cand = context:get_selected_candidate()
    if not cand or not cand.text or cand.text == "" then
        return kNoop
    end

    local english = find_translation(cand, env.mapping)
    if not english or english == "" then
        return kNoop
    end

    engine:commit_text(english)
    context:clear()
    return kAccepted
end

-- 释放当前处理器持有的映射引用。
function M.fini(env)
    env.mapping = nil
    env.shift_pending = nil
end

return M
