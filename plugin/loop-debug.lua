-- IMPORTANT: keep this module light for lazy loading

require('loop.extensions').register_extension({
    name = "debug",
    module = "loop-debug.ext",
    is_cmd_provider = true,
    is_task_provider = true,
})
