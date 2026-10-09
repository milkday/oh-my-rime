-- 仅为当前高亮的中文候选项追加英文翻译注释。

local cn_en_mapping = require("cn_en_mapping")

local M = {}

-- 高亮变化时重建候选注释，并保留当前选择和翻页状态。
local function refresh_selected_translation(context, env)
    if env.refreshing then
        return
    end

    local composition = context.composition
    local segment = not composition:empty() and composition:back() or nil
    if not segment or not segment.menu or segment.status ~= "kGuess" then
        env.selected_index = nil
        return
    end

    local selected_index = segment.selected_index
    if env.selected_index ~= nil and selected_index ~= env.selected_index then
        local paging = segment:has_tag("paging")
        env.refreshing = true
        env.refresh_index = selected_index
        context:refresh_non_confirmed_composition()

        segment = not context.composition:empty() and context.composition:back() or nil
        if not segment or not segment.menu then
            env.refresh_index = nil
            env.refreshing = false
            env.selected_index = nil
            return
        end
        local count = segment.menu:prepare(selected_index + 1)
        segment.selected_index = math.max(0, math.min(selected_index, count - 1))
        if paging then
            segment.tags = segment.tags + Set({ "paging" })
        end
        env.refresh_index = nil
        env.refreshing = false
    end

    env.selected_index = segment.selected_index
end

-- 初始化候选注释配置并设置共享分片缓存容量。
function M.init(env)
    local config = env.engine.schema.config
    local name_space = env.name_space:gsub("^%*", "")

    env.enable = config:get_bool(name_space .. "/enable")
    if env.enable == nil then
        env.enable = true
    end

    env.show_for_single_char = config:get_bool(name_space .. "/show_for_single_char")
    if env.show_for_single_char == nil then
        env.show_for_single_char = false
    end

    env.format = config:get_string(name_space .. "/format") or " / {english}"
    env.format_has_placeholder = env.format:find("{english}", 1, true) ~= nil
    env.only_for_types = {}

    local types_list = config:get_list(name_space .. "/only_for_types")
    if types_list then
        for i = 0, types_list.size - 1 do
            local type_value = types_list:get_value_at(i).value
            env.only_for_types[type_value] = true
        end
    end

    cn_en_mapping.configure(config:get_int("cn_en_translation/cache_size"))
    env.mapping = cn_en_mapping.mapping
    if env.enable then
        env.update_connection = env.engine.context.update_notifier:connect(function(context)
            refresh_selected_translation(context, env)
        end)
    end
end

-- 判断候选文本是否以常用中文字符开头。
local function is_chinese_text(text)
    if not text or text:len() < 3 then
        return false
    end

    local first_byte = text:byte(1)
    return first_byte >= 224 and first_byte <= 233
end

-- 取得候选显示文本及其原始中文文本。
local function candidate_texts(cand)
    local visible_text = cand.text
    local genuine = cand:get_genuine()
    local original_text = genuine and genuine.text or visible_text
    return visible_text, original_text, genuine
end

-- 按去重后的候选序号，仅为本轮高亮项查询并追加英文注释。
function M.func(input, env)
    local selected_index = env.refresh_index or 0
    env.selected_index = selected_index
    local index = -1
    local seen = {}
    for cand in input:iter() do
        local first_occurrence = not seen[cand.text]
        if first_occurrence then
            seen[cand.text] = true
            index = index + 1
        end
        if env.enable and first_occurrence and index == selected_index then
            local visible_text, original_text, genuine = candidate_texts(cand)
            local lookup_text = original_text or visible_text
            local type_allowed = next(env.only_for_types) == nil or env.only_for_types[cand.type] ~= nil
            local length_allowed = env.show_for_single_char or lookup_text:len() > 3

            if is_chinese_text(lookup_text) and type_allowed and length_allowed then
                local english = env.mapping[lookup_text]
                if not english and visible_text ~= lookup_text then
                    english = env.mapping[visible_text]
                end

                if english then
                    local annotation
                    if env.format_has_placeholder then
                        annotation = env.format:gsub("{english}", function()
                            return english
                        end)
                    else
                        annotation = env.format .. english
                    end

                    local comment = cand.comment or ""
                    local translated_comment = comment .. annotation
                    if cand:get_dynamic_type() == "Shadow" then
                        cand = ShadowCandidate(genuine, genuine.type, visible_text, translated_comment)
                    else
                        cand.comment = translated_comment
                    end
                end
            end
        end

        yield(cand)
    end
end

-- 断开更新通知并释放候选及映射引用。
function M.fini(env)
    if env.update_connection then
        env.update_connection:disconnect()
        env.update_connection = nil
    end
    env.selected_index = nil
    env.mapping = nil
end

return M
