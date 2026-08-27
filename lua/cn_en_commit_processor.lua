-- 在候选菜单中按 Shift+Space，上屏当前中文候选的英文映射。

local cn_en_mapping = require("cn_en_mapping")

local M = {}
local kAccepted = 1
local kNoop = 2

-- 初始化英文上屏快捷键并设置共享分片缓存容量。
function M.init(env)
    local config = env.engine.schema.config
    local name_space = env.name_space:gsub("^%*", "")

    env.enable = config:get_bool(name_space .. "/enable")
    if env.enable == nil then
        env.enable = true
    end

    env.commit_english_key = config:get_string(name_space .. "/commit_english_key") or "Shift+space"
    cn_en_mapping.configure(config:get_int("cn_en_translation/cache_size"))
    env.mapping = cn_en_mapping.mapping
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

-- 处理英文上屏快捷键。
function M.func(key, env)
    if not env.enable or key:release() or key:repr() ~= env.commit_english_key then
        return kNoop
    end

    local engine = env.engine
    local context = engine.context
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
end

return M
