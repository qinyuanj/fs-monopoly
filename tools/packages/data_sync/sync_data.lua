-- packages/data_sync/sync_data.lua —— sync-data 子命令实现(Data 回同步)
--
-- 方向与 deploy 相反:从部署目录(Eggy 宿主侧 LuaSource_大富翁/)把编辑器
-- 最新导出回同步进仓库:
--   Data/Prefab.lua → Data/Prefab.lua 字节原样拷贝(编辑器导出格式即仓内格式,无需转换)
--   Data/UINodes.lua → 转换为 Data/UIManagerNodes.lua(以节点 id 为键聚合、
--     按 id 升序、值 {"名称","类型"});转换逻辑移植自 UIManager_web 小工具的
--     script.js UINodesMerger,导出末尾不再生成 length 行(仓内旧文件尾部的
--     --length 注释行随之消失)。
--   EggyAPI.lua / EggyEditorAPI.lua → 仓库根同名文件,字节原样拷贝
--     (宿主侧 API 存根为第三方边界,编辑器更新后随之回同步)。
--
-- 部署目录 / 仓库根解析复用 packages.ops.deploy(WSL 互操作,ADR 0073),
-- 不重复实现。纯模块,无独立脚本入口:由 packages/data_sync/cli.lua 进程内调用
-- (package.path 经 tools/cli.lua 装配,可直接 require foundation.* / packages.*)。
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local deploy = require("packages.ops.deploy")

local M = {}

local HEADER = "---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT"

-- 单行解析,对应 JS
--   /^\s*(?:--\s*)?(?:\["([^"]+)"\]|(\w+))\s*=\s*"([^"]+)"\s*--\[\[@as\s+(\w+)\]\]/
-- 整行被 -- 注释掉的条目同样收养(编辑器导出会把删掉的节点注释保留);行尾逗号
-- 等残余不校验(JS 正则同样未锚定行尾);\w 对齐 JS 语义(ASCII 字母数字 + _,
-- 中文名键只会走 ["..."]  bracket 形式)。
local function _parse_line(line)
  local body = line:match("^%s*(.-)%s*$") or ""
  body = body:gsub("^%-%-%s*", "")
  local name, id, node_type = body:match('^%["([^"]+)"%]%s*=%s*"([^"]+)"%s*%-%-%[%[@as%s+([%w_]+)%]%]')
  if name == nil then
    name, id, node_type = body:match('^([%w_]+)%s*=%s*"([^"]+)"%s*%-%-%[%[@as%s+([%w_]+)%]%]')
  end
  return name, id, node_type
end

-- UINodes.lua 文本 → { [id] = { name = ..., node_type = ... } };同 id 后者覆盖
-- (与 JS 以 id 为键直接赋值一致)。
function M.parse_uinodes(text)
  local data = {}
  for raw_line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local name, id, node_type = _parse_line(raw_line:gsub("\r$", ""))
    if name ~= nil then
      data[id] = { name = name, node_type = node_type }
    end
  end
  return data
end

-- 渲染 UIManagerNodes.lua:id 按字节序升序(JS Array.prototype.sort 对纯 ASCII
-- id 等价);无 length 行。
function M.render_ui_manager_nodes(data)
  local ids = {}
  for id in pairs(data) do
    ids[#ids + 1] = id
  end
  table.sort(ids)

  local lines = { HEADER, "", "return {" }
  for _, id in ipairs(ids) do
    local item = data[id]
    lines[#lines + 1] = string.format('\t["%s"] = {"%s", "%s"},', id, item.name, item.node_type)
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

local function _count_keys(map)
  local count = 0
  for _ in pairs(map) do
    count = count + 1
  end
  return count
end

-- 回同步主流程:deploy_dir/Data/{Prefab.lua,UINodes.lua}
--   → repo_root/Data/{Prefab.lua,UIManagerNodes.lua};
-- deploy_dir/{EggyAPI.lua,EggyEditorAPI.lua} → repo_root 同名文件(字节原样)。
-- 成功返回 stats 表;失败返回 nil, err(不写任何文件,解析前置校验全过才落盘)。
function M.sync_from_deploy(deploy_dir, repo_root)
  local source_data = path_lib.join_path(deploy_dir, "Data")
  local prefab_src = path_lib.join_path(source_data, "Prefab.lua")
  local uinodes_src = path_lib.join_path(source_data, "UINodes.lua")
  local api_src = path_lib.join_path(deploy_dir, "EggyAPI.lua")
  local editor_api_src = path_lib.join_path(deploy_dir, "EggyEditorAPI.lua")

  if not fs_lib.path_exists(prefab_src) then
    return nil, "部署目录缺少 Data/Prefab.lua: " .. tostring(prefab_src)
  end
  if not fs_lib.path_exists(uinodes_src) then
    return nil, "部署目录缺少 Data/UINodes.lua: " .. tostring(uinodes_src)
  end
  if not fs_lib.path_exists(api_src) then
    return nil, "部署目录缺少 EggyAPI.lua: " .. tostring(api_src)
  end
  if not fs_lib.path_exists(editor_api_src) then
    return nil, "部署目录缺少 EggyEditorAPI.lua: " .. tostring(editor_api_src)
  end

  local prefab_new, prefab_err = fs_lib.read_file(prefab_src)
  if prefab_new == nil then
    return nil, prefab_err
  end
  local uinodes_text, uinodes_err = fs_lib.read_file(uinodes_src)
  if uinodes_text == nil then
    return nil, uinodes_err
  end
  local api_new, api_err = fs_lib.read_file(api_src)
  if api_new == nil then
    return nil, api_err
  end
  local editor_api_new, editor_api_err = fs_lib.read_file(editor_api_src)
  if editor_api_new == nil then
    return nil, editor_api_err
  end

  local parsed = M.parse_uinodes(uinodes_text)
  local node_count = _count_keys(parsed)
  if node_count == 0 then
    return nil, "UINodes.lua 未解析出任何节点,导出格式可能已变化: " .. tostring(uinodes_src)
  end
  local nodes_new = M.render_ui_manager_nodes(parsed)

  local target_data = path_lib.join_path(repo_root, "Data")
  local prefab_dst = path_lib.join_path(target_data, "Prefab.lua")
  local nodes_dst = path_lib.join_path(target_data, "UIManagerNodes.lua")
  local api_dst = path_lib.join_path(repo_root, "EggyAPI.lua")
  local editor_api_dst = path_lib.join_path(repo_root, "EggyEditorAPI.lua")
  local prefab_old = fs_lib.read_file(prefab_dst)
  local nodes_old = fs_lib.read_file(nodes_dst)
  local api_old = fs_lib.read_file(api_dst)
  local editor_api_old = fs_lib.read_file(editor_api_dst)

  local ok, write_err = fs_lib.write_file(prefab_dst, prefab_new)
  if not ok then
    return nil, write_err
  end
  ok, write_err = fs_lib.write_file(nodes_dst, nodes_new)
  if not ok then
    return nil, write_err
  end
  ok, write_err = fs_lib.write_file(api_dst, api_new)
  if not ok then
    return nil, write_err
  end
  ok, write_err = fs_lib.write_file(editor_api_dst, editor_api_new)
  if not ok then
    return nil, write_err
  end

  return {
    prefab_bytes = #prefab_new,
    prefab_changed = prefab_old ~= prefab_new,
    node_count = node_count,
    nodes_changed = nodes_old ~= nodes_new,
    api_bytes = #api_new,
    api_changed = api_old ~= api_new,
    editor_api_bytes = #editor_api_new,
    editor_api_changed = editor_api_old ~= editor_api_new,
  }
end

local function _change_flag(changed)
  return changed and "有更新" or "无变化"
end

-- CLI 主流程:零参数;返回退出码(0 成功 / 1 业务失败 / 2 用法错误);不在 WSL 时
-- resolve_platform_name 直接退 3。
function M.main(args)
  if args ~= nil and #args > 0 then
    io.stderr:write("ERROR: Unexpected argument: " .. table.concat(args, " ") .. "\n")
    return 2
  end

  -- 缺 WSL 互操作面时 resolve_platform_name 内部直接退 3(status=unavailable,deploy 语义)。
  deploy.resolve_platform_name()
  local deploy_dir = deploy.resolve_default_target_path()
  local repo_root = deploy.resolve_project_root()

  io.stdout:write("======================================\n")
  io.stdout:write("Data sync-back (deploy dir -> repo)\n")
  io.stdout:write("======================================\n")
  io.stdout:write("Deploy dir: " .. tostring(deploy_dir) .. "\n")
  io.stdout:write("Repo root: " .. tostring(repo_root) .. "\n")

  local stats, err = M.sync_from_deploy(deploy_dir, repo_root)
  if stats == nil then
    io.stderr:write("ERROR: " .. tostring(err) .. "\n")
    return 1
  end

  io.stdout:write(string.format(
    "Prefab.lua        : %d bytes (%s)\n",
    stats.prefab_bytes,
    _change_flag(stats.prefab_changed)
  ))
  io.stdout:write(string.format(
    "UIManagerNodes.lua: %d nodes (%s)\n",
    stats.node_count,
    _change_flag(stats.nodes_changed)
  ))
  io.stdout:write(string.format(
    "EggyAPI.lua       : %d bytes (%s)\n",
    stats.api_bytes,
    _change_flag(stats.api_changed)
  ))
  io.stdout:write(string.format(
    "EggyEditorAPI.lua : %d bytes (%s)\n",
    stats.editor_api_bytes,
    _change_flag(stats.editor_api_changed)
  ))
  return 0
end

return M
