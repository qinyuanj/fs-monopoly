local runtime_ports = require("src.foundation.ports.runtime_ports")

local clock_ports = {}

function clock_ports.build()
  return {
    wall_now_seconds = function()
      return runtime_ports.wall_now_seconds()
    end,
    wall_diff_seconds = function(timestamp_1, timestamp_2)
      return runtime_ports.wall_diff_seconds(timestamp_1, timestamp_2)
    end,
    cpu_now_seconds = function()
      return runtime_ports.cpu_now_seconds()
    end,
    cpu_diff_seconds = function(timestamp_1, timestamp_2)
      return runtime_ports.cpu_diff_seconds(timestamp_1, timestamp_2)
    end,
  }
end

return clock_ports

