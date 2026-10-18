require("test.bootstrap").install_package_paths()

local guard_support = require("test.support.guards.guard_support")

local function _scan_rule(rule)
  return guard_support.find_line_violation({
    roots = rule.roots,
    find_violation = function(path, relpath, line, line_number)
      for _, token in ipairs(rule.forbidden or {}) do
        if line:find(token, 1, true) then
          return {
            path = relpath,
            line = line_number,
            token = token,
            text = line,
            description = rule.description,
          }
        end
      end

      for _, pattern in ipairs(rule.forbidden_patterns or {}) do
        if line:find(pattern) then
          return {
            path = relpath,
            line = line_number,
            token = pattern,
            text = line,
            description = rule.description,
          }
        end
      end

      return nil
    end,
  })
end

local function _check_forbidden_files(paths)
  for _, path in ipairs(paths or {}) do
    local file = io.open(path, "r")
    if file then
      file:close()
      return {
        path = path,
        line = 1,
        token = "forbidden_file",
        text = path,
        description = "forbidden file exists",
      }
    end
  end
  return nil
end

-- Only configured calls use full-source parsing; existing line rules keep their scanner.
local function _scan_call_rule(rule)
  local ast = require("test.guards.lib.test_lint.ast")
  local function find_call(node)
    if type(node) ~= "table" then return nil end
    if node.tag == "Call" then
      local callee = node[1]
      local name = ast.id_name(callee)
      if callee.tag == "Index" and callee[2].tag == "String" then name = callee[2][1] end
      local pattern = rule.forbidden_call_paths[name]
      if pattern then
        local arg = node[2]
        local values = name == "run_command" and arg and arg.tag == "Table" and arg or { arg }
        for _, value in ipairs(values) do
          if value.tag == "String" and value[1]:find(pattern) then
            return { line = node.line, token = pattern, text = name .. ": " .. value[1], description = rule.description }
          end
        end
      end
    end
    for _, child in ipairs(node) do
      local hit = find_call(child)
      if hit then return hit end
    end
  end
  for _, root in ipairs(rule.roots or {}) do
    local files, err = guard_support.collect_lua_files(root)
    if not files then return nil, err end
    for _, path in ipairs(files) do
      local file, open_err = io.open(path, "r")
      if not file then return nil, open_err end
      local source = file:read("*a")
      file:close()
      local parsed, parse_err = ast.parse(source)
      if not parsed then return nil, path .. ": " .. tostring(parse_err) end
      local hit = find_call(parsed.ast)
      if hit then
        hit.path = guard_support.normalize_path(path)
        return hit
      end
    end
  end
end

local M = {}

function M.run(opts)
  opts = opts or {}
  for _, rule in ipairs(opts.rules or {}) do
    local hit, err = _scan_rule(rule)
    if not hit and not err and rule.forbidden_call_paths then
      hit, err = _scan_call_rule(rule)
    end
    if err and not tostring(err):find("no lua files found under", 1, true) then
      return { ok = false, error = err }
    end
    if hit then
      return { ok = false, violation = hit }
    end
  end

  local forbidden_file_hit = _check_forbidden_files(opts.forbidden_files)
  if forbidden_file_hit then
    return { ok = false, violation = forbidden_file_hit }
  end

  return { ok = true, message = "dep_rules ok" }
end

return M
