local M = {}

--[[

    local variables_comp = VariablesComp:new(task_name)
    local stacktrace_comp = StackTraceComp:new(task_name)


    local vars_page = page_manager.add_page_group(_page_groups.variables, "Variables").add_page(_page_groups.variables,
        "Variables")
    local stack_page = page_manager.add_page_group(_page_groups.stack, "Call Stack").add_page(_page_groups.stack,
        "Call Stack")

    variables_comp:link_to_page(vars_page)
    stacktrace_comp:link_to_page(stack_page)


]]

return {}