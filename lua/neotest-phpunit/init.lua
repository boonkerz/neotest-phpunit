local lib = require('neotest.lib')
local logger = require('neotest.logging')
local async = require('neotest.async')
local adapter = { name = 'neotest-phpunit' }

adapter.root = lib.files.match_root_pattern('composer.json')

function adapter.is_test_file(file_path)
  if string.match(file_path, "vendor") then
      return false
  end
  return vim.endswith(file_path, "Test.php")
end

function adapter.build_spec(args)
  local results_path = vim.fn.tempname() .. '.xml'
  local tree = args.tree
  if not tree then
    return
  end
  local pos = args.tree:data()
  local testNamePattern = '.*'
  if pos.type == 'test' then
    testNamePattern = pos.name
  end

  local binary = 'phpunit'
  if vim.fn.filereadable('vendor/bin/phpunit') then
    binary = 'vendor/bin/phpunit'
  end

  local command = vim.tbl_flatten({
    binary,
    pos.path,
    '--log-junit='..results_path 
  })
  logger.error('phpunit_command', command)
  return {
    command = command,
    context = {
      results_path = results_path,
      file = pos.path,
    },
  }
end

function adapter.results(spec, result)
  local results = {}

  local success, data = pcall(lib.files.read, spec.context.results_path)

  if not success then
    results = "{}"
  end
  local parsedXml = lib.xml.parse(data)
  for _, containerSuite in pairs(parsedXml.testsuites) do
    for __, testsuite in pairs(containerSuite.testsuite) do
        for ___,testcase in pairs(testsuite.testcase) do
            local error = { message = "Error", line = 15 }
            local alias_id = ""
            if testcase['_attr'] then
                alias_id = testcase._attr.file .. '::' .. testcase._attr.name
            elseif testcase["name"] then
                alias_id = testcase.file .. '::' .. testcase.name
            end
            
            if not testcase["failure"] then
                results[alias_id] = { status = "passed", short = "", output = ""}
            else
                local fname = async.fn.tempname()
                vim.fn.writefile({testcase.failure[1]}, fname)
                results[alias_id] = { status = "failed", short = testcase.failure[1], output = fname, errors = {error} }
            end
        end
    end
  end
  return results
end

local function generate_position_id(position, namespaces)
    local id = table.concat(
        vim.tbl_flatten({
          position.path,
          position.name,
        }),
        "::"
    )   
    logger.error("generate_position_id", id)
    return id
end

function adapter.discover_positions(path)
    local query = [[
    (method_declaration
        name: (name) @test.name
        (#match? @test.name "test"))
        @test.definition

    (namespace_definition
        name: (namespace_name) @namespace.name)
        @namespace.definition
    ]]
  return lib.treesitter.parse_positions(path, query, { nested_namespace = true, position_id = generate_position_id })
end

setmetatable(adapter, {
  __call = function()
    return adapter
  end,
})

return adapter