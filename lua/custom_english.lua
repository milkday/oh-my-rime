-- 运行时英文个人词库：保存快捷键收录的英文词，并按小写编码提供候选。
local M = {
    words = {},
    path = nil,
}

-- 取得个人词库文件路径并加载已有词条。
function M.init()
    if M.path then
        return
    end
    M.path = rime_api.get_user_data_dir() .. "/custom_english.txt"
    local file = io.open(M.path, "r")
    if not file then
        return
    end
    for line in file:lines() do
        local code, text = line:match("^([^\t]+)\t(.+)$")
        if code and text and text:match("^[A-Za-z]+$") and code == text:lower() then
            M.words[code:lower()] = text
        end
    end
    file:close()
end

-- 将一个英文词写入个人词库，并立即更新内存索引。
function M.add(text)
    M.init()
    local code = text:lower()
    if M.words[code] == text then
        return true
    end
    local file = io.open(M.path .. ".tmp", "w")
    if not file then
        return false
    end
    local codes = {}
    for saved_code in pairs(M.words) do
        if saved_code ~= code then
            codes[#codes + 1] = saved_code
        end
    end
    codes[#codes + 1] = code
    table.sort(codes)
    local written = true
    for _, saved_code in ipairs(codes) do
        if not file:write(saved_code, "\t", saved_code == code and text or M.words[saved_code], "\n") then
            written = false
            break
        end
    end
    local closed = file:close()
    if not written or not closed or not os.rename(M.path .. ".tmp", M.path) then
        os.remove(M.path .. ".tmp")
        return false
    end
    M.words[code] = text
    return true
end

-- 为当前输入生成英文候选。
function M.func(input, seg, env)
    M.init()
    if seg.start ~= 0 or seg._end ~= #env.engine.context.input then
        return
    end
    local text = M.words[input:lower()]
    if text then
        local cand = Candidate("custom_english", seg.start, seg._end, text, "")
        cand.quality = 10
        yield(cand)
    end
end

return M
