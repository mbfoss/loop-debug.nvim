local schema = {
    type = "object",
    required = { "debugger", "request" },
    additionalProperties = true,
    properties = {
        debugger = {
            type = { "string" },
            description = "debugger type"
        },
        request = {
            type = { "string" },
            description = "task.request must be 'launch' or 'attach'"
        },
    }
}

return schema
