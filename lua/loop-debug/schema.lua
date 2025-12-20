local schema = {
    type = "object",
    required = { "command", "cwd" },
    properties = {
        name = {
            type = "string",
            minLength = 1,
            description = "Non-empty task name (supports ${VAR} templates)"
        },
        type = {
            type = "string",
            enum = { "composite" },
            description = "Task category"
        },
        command = {
            description =
            "Command to run (string or array of strings). nil allowed for some types (e.g., debug).",
            oneOf = {
                { type = "string", minLength = 1 },
                {
                    type = "array",
                    minItems = 1,
                    items = { type = "string", minLength = 1 }
                },
                { type = "null" }
            }
        },
        cwd = {
            type = { "string", "null" },
            description = "Optional working directory (supports ${VAR} templates)"
        },
        env = {
            type = { "object", "null" },
            additionalProperties = { type = "string" },
            description = "Optional environment variables (key-value pairs of strings)"
        },
        quickfix_matcher = {
            type = { "string", "null" },
            description = "Optional quickfix matcher name"
        },
        depends_on = {
            type = { "array", "null" },
            items = { type = "string", minLength = 1 },
            description = "Optional list of dependent task names"
        },
        debug = {
            type = { "object", "null" },
            additionalProperties = true,
            required = { "type", "request" },
            properties = {
                type = {
                    type = "string",
                    description = "Debug adapter type/name"
                },
                request = {
                    type = "string",
                    enum = { "launch", "attach" },
                    description = "Debug request type"
                }
            },
            description = "Optional debug configuration (primarily for type = 'debug')"
        }
    },
    dependencies = {
        debug = { properties = { type = { const = "debug" } } }
    }
}

return schema
