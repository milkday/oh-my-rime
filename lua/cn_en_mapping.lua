-- 中英文映射词典：按首字分片加载，并使用共享 LRU 限制常驻分片数量。

local M = {}

local shard_index = require("cn_en_shards_index").shards
local DEFAULT_CACHE_SIZE = 32

local cache_size = DEFAULT_CACHE_SIZE
local cache_count = 0
local cache = {}
local cache_head = nil
local cache_tail = nil

-- 根据中文首字生成对应的分片名称。
local function shard_key(text)
    if not text or text == "" then
        return nil
    end

    local first_char = text:sub(1, 3)
    local bytes = { first_char:byte(1, #first_char) }
    local parts = {}
    for _, byte in ipairs(bytes) do
        parts[#parts + 1] = string.format("%02x", byte)
    end
    return "u" .. table.concat(parts, "_")
end

-- 从 LRU 双向链表中移除节点。
local function detach(node)
    if node.previous then
        node.previous.next = node.next
    else
        cache_head = node.next
    end

    if node.next then
        node.next.previous = node.previous
    else
        cache_tail = node.previous
    end

    node.previous = nil
    node.next = nil
end

-- 将节点移动到 LRU 链表头部。
local function move_to_front(node)
    if cache_head == node then
        return
    end

    if node.previous or node.next or cache_tail == node then
        detach(node)
    end

    node.next = cache_head
    if cache_head then
        cache_head.previous = node
    else
        cache_tail = node
    end
    cache_head = node
end

-- 淘汰最久未使用的分片并释放 Lua 模块缓存。
local function evict_oldest()
    local node = cache_tail
    if not node then
        return
    end

    detach(node)
    cache[node.key] = nil
    package.loaded[node.module_name] = nil
    node.mapping = nil
    cache_count = cache_count - 1
end

-- 加载或从 LRU 缓存中取得指定分片。
local function load_shard(key)
    if not key or not shard_index[key] then
        return nil
    end

    local cached = cache[key]
    if cached then
        move_to_front(cached)
        return cached.mapping
    end

    local module_name = "cn_en_shards." .. key
    local ok, module = pcall(require, module_name)
    if not ok or not module or not module.mapping then
        package.loaded[module_name] = nil
        return nil
    end

    local node = {
        key = key,
        module_name = module_name,
        mapping = module.mapping,
    }
    cache[key] = node
    cache_count = cache_count + 1
    move_to_front(node)

    while cache_count > cache_size do
        evict_oldest()
    end

    return node.mapping
end

-- 设置共享 LRU 最多保留的分片数量。
function M.configure(max_shards)
    local configured_size = math.floor(tonumber(max_shards) or DEFAULT_CACHE_SIZE)
    cache_size = math.max(1, configured_size)

    while cache_count > cache_size do
        evict_oldest()
    end
end

-- 清空所有已加载分片，供重新部署或调试时主动释放。
function M.clear_cache()
    while cache_tail do
        evict_oldest()
    end
end

-- 查询指定中文文本的英文映射。
function M.get_translation(chinese_text)
    local shard = load_shard(shard_key(chinese_text))
    if not shard then
        return nil
    end
    return shard[chinese_text]
end

M.mapping = setmetatable({}, {
    __index = function(_, chinese_text)
        return M.get_translation(chinese_text)
    end,
})

return M
