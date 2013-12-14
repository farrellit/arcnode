--[[
local function log (msg) 
	redis.log( redis.LOG_NOTICE, msg )
end
local function notice (msg) 
	redis.log( redis.LOG_NOTICE, debug.traceback() .. "\n" .. msg )
end
--]]
local function type_assert ( var, target_type, msg, neg )
	if not msg then
		local type_message
		if neg then
			type_message = "not " .. target_type
		else
			type_message = target_type
		end
		msg = "Wrong type ("..type(msg) .. ") : expected " .. type_message .. " in: \n"..debug.traceback() 
	end
	if neg then
		assert( not( type(var) == target_type), msg )
	else
		assert( type(var) == target_type,  msg )
	end
end

local function showtable( tbl )
	local msg = type(tbl) .. " {"
	local count=0
	for k,v in pairs(tbl) do 
		count = count + 1
		if count > 1 then
			msg  = msg .. ","
		end
		msg = msg .. k .. "=" 
		if type(v) == 'table' then
			msg = msg .. showtable(v)
		else
			msg = msg .. "\"" .. tostring(v) .. "\""
		end
	end
	msg = msg .. "}"
	return msg 
end

local tools={}

tools.index = {}

tools.index.next_id = function ( opts )
	assert( type(opts) == 'table', "tools.index.next_id: opts must be table" )
	assert( type(opts['index'] ) == 'string', "tools.index.next_id: opts['index'] must be string" )
	if not( type(opts['counter']) == 'string' ) then
		opts['counter'] = opts['index'] .. "_last_id"
	end
	local i = 0
	while i == 0  do
		i = tonumber( redis.call( "INCR", opts['counter'] ) )
		if tools.index.exists( { index=opts['index'], value=i} ) then
			--[[notice( "\"Unused\" ID ".. i  .. " from " .. opts['counter'] 
				.. " already existed in " .. opts['index'] 
				.. " : choosing another " )
			--]]
			i = 0
		end
	end
	return i
end

tools.index.all = function( opts )
	type_assert( opts, 'table' )
	type_assert( opts.index, 'nil', nil, true )
	return redis.call( 'SMEMBERS', opts.index )
end

tools.index.add = function ( opts )
	local function badinput_msg (submsg ) 
		return "Bad input to index.add : ".. submsg 
			.. "opts: table containing:\n" 
			.. "		'index' : the index for this record \n" 
			.. "		'value' : the id for this record \n"
	end

	assert( type(opts) == 'table', badinput_msg("opts must be of type table") )
	assert( not( type(opts['index']) == "nil"), badinput_msg("opts['index'] must be defined") )
	assert( not(type(opts['value']) ==  "nil"), badinput_msg("opts['value'] must be defined") )

	redis.call( 'sadd', opts['index'], opts['value'] )

	return true
end

tools.index.exists = function ( opts ) 
	assert( type(opts) == 'table', "tools.index.exists - opts must be of type table " .. debug.traceback() ) 
	assert( not(type(opts['index']) == "nil"), "opts['index'] must be defined" )
	assert( not(type(opts['value']) ==  "nil"), "opts['value'] must be defined" )
	local ret = true
	if tonumber( redis.call( "SISMEMBER", opts['index'], opts['value'] ) ) == 0 then
		ret = false
	end
	return ret
end	

tools.index.del = function ( opts )
	assert( type(opts) == 'table', "tools.index.del - opts must be of type table " .. debug.traceback() ) 
	assert( not(type(opts['index']) == "nil"), "opts['index'] must be defined" )
	assert( not(type(opts['value']) ==  "nil"), "opts['value'] must be defined" )
	local ret = true
	return tonumber( redis.call( "SREM", opts['index'], opts['value'] ) )
end

tools.index.cross = function ( opts )
	local function badinput_msg (submsg ) 
		return "Bad input to index.cross_index: ".. submsg 
				 .. "opts[2], optsions[1]: tables representing records to index.cross_index, each containing:\n"
				 .. "'index' : the index for this record\n" 
				 .. "'value' : the id for this record "
				 .. "Each record's id will be added to the other's index."
	end
	assert( type(opts) == 'table', badinput_msg("opts must be of type table") )
	for i in pairs({ 1, 2 }) do
		assert( type(opts[i]) == "table", badinput_msg("opts["..i.."] must be of type table" ) )
		assert( not(type(opts[i]['index']) == "nil"), badinput_msg("opts["..i.."]['index'] must be of type string") )
		assert( not(type(opts[i]['value']) ==  "nil"), badinput_msg("opts["..i.."]['value'] must be of type string") )
	end
	--log( "tools.index.cross : crossing: " .. showtable( opts )) 
	redis.call( 'sadd', opts[1]['index'], opts[2]['value'] )
	redis.call( 'sadd', opts[2]['index'], opts[1]['value'] )
	return true
end

tools.index.uncross = function ( opts ) 
	assert( type(opts) == 'table', "tools.index.uncross - opts must be of type table " .. debug.traceback() ) 
	for i in pairs({ 1, 2 }) do
		assert( type(opts[i]) == "table", "opts["..i.."] must be of type table"  )
		assert( not(type(opts[i]['index']) == "nil"), "opts["..i.."]['index'] must be of type string" )
		assert( not(type(opts[i]['value']) ==  "nil"), "opts["..i.."]['value'] must be of type string" )
	end
	--log( "tools.index.cross : uncrossing: " .. showtable( opts ) ) 
	redis.call( 'SREM', opts[1]['index'], opts[2]['value'] )
	redis.call( 'SREM', opts[2]['index'], opts[1]['value'] )
	return true
end

tools.arcnode = {}

tools.arcs = {}

tools.arcs.config = { 
	name="arcs",
	index="arcs",
	each_indices = { 
		nodes=function (id) return "arcs_"..id.."_nodes" end
	},
	each_templates= {
		id={ 
			genname=function (id) return "arcs_"..id end,
			attributes={
				factor_atrophy=1.0,
				factor_wear=1.0,
				count_traversals=0
			}
		}
	}
}

tools.arcs.exists = function ( opts )
	assert( type(opts) == 'table', "tools.arcs.exists: opts must be table" )
	assert( not(type(opts['id']) == 'nil'), "tools.arcs.exists: opts['id'] must be set" )
	return tools.index.exists( { index=tools.arcs.config.index , value=opts['id'] } )
end

tools.arcnode.create = function ( opts )
	assert( type(opts) == 'table', 
		"tools.arcnode.create: opts must be table" )
	assert( type(opts.config) == 'table', 
		"tools.arcnode.create: opts['config'] must be table" )
	local config = opts.config
	local id = tools.index.next_id( { index=config.index } )
	assert( not (type(id) == nil), "Failed to gain an ID!" )
	--log( "Type of id is " .. type(id) )
	--log( "New id for " .. opts.config.name .. " is " .. id )
	for i,tpl in pairs(config.each_templates) do
		local tplname=tpl.genname( id )
		for attr,value in pairs(tpl.attributes) do
			redis.call( "HSETNX", tplname, attr, value )
		end
	end
	for rel,ifunc in pairs( config.each_indices ) do
		assert( type(opts[rel] ) == 'table', "config.each_indexes entry '"..rel.."' missing from opts" )
		for i,other in pairs( opts[rel] ) do 
			tools.index.cross( { 
				{ index=ifunc(id), value=id },
				{ index=tools[rel].config.each_indices[config.name](other), value=other }
			} )
		end
	end
	tools.index.add( { index=config.index, value=id } )
	redis.call( 'HSET', config.each_templates.id.genname( id ), 'id', id)
	return id
end
--[[
tools.logdel =function( key ) 
	log( "delete " .. key )
	redis.call( "DEL",  key )
end
--]]
tools.arcnode.std_assert = function( opts )
	type_assert( opts, 'table')
	type_assert( opts.id, 'nil', nil, true )
end

tools.arcnode.delete = function( opts )
	type_assert( opts.config, 'table')
	local tool = tools[opts.config.name]
	type_assert( tool, "table" , "Could not find tool for " .. opts.config.name .. " in tools.arcnode.create " )
	local t = {}
	assert( tool.exists( {id=opts.id} ), 
		"Does not exist: " .. opts.config.name .. " id " 
			..  opts.id 
		)
	tools.index.del( { index=opts.config.index, value=opts.id } )
	for rel,ifunc in pairs( opts.config.each_indices ) do
		for i,other in pairs( tools.index.all( {index=ifunc(opts.id)} ) ) do
			tools.index.uncross( { 
				{ index=ifunc(opts.id), value=opts.id },
				{ index=tools[rel].config.each_indices[opts.config.name](other), value=other }
			} )
		end
		--tools.logdel( ifunc(opts.id) )
	end
	for i,tpl in pairs(opts.config.each_templates) do
		--tools.logdel( tpl.genname( opts.id ) )
	end
	return opts.id
end
	

tools.arcs.create = function ( opts )
	assert( type(opts) == 'table', 
		"tools.arcs.create: opts must be table" )
	assert( type(opts['nodes']) == 'table', 
		"tools.arcs.create: opts['nodes'] must be table")
	assert( not ( type(opts['nodes'][2]) == nil or type(opts['nodes'][1]) == nil ), 
		"tools.arcs.create: opts['nodes'] must contain 2 node IDs " )
	for i in pairs({ 1, 2}) do 
		local n={ 1,2,3 }
		assert(tools.nodes.exists( { t=n, id=opts.nodes[i] } ), "node does not exist: " .. opts.nodes[i] )
	end
	assert( not( opts.nodes[1] == opts.nodes[2] ), 
		"tools.arcs.create: nodes must be different, not just {1=#"..opts.nodes[1]..",2="..opts.nodes[2].."}" )
	for i,k in pairs( redis.call( 'smembers', tools.nodes.config.each_indices.arcs( opts.nodes[1])) ) do
		assert( 0 == redis.call('sismember', tools.nodes.config.each_indices.arcs( opts.nodes[2] ), k), 
			" Arc " .. k .. " already joins  " .. 
				showtable(redis.call('smembers', tools.arcs.config.each_indices.nodes( k ) ) ) 
			.. " options are: " .. opts.nodes[1] .. " and ".. opts.nodes[2] .. "\n" .. 
			  "found in " .. tools.nodes.config.each_indices.arcs( opts.nodes[1] ) ..  " " 
			  .. showtable(redis.call( 'smembers', tools.nodes.config.each_indices.arcs( opts.nodes[1])) )
			  .. " \n and \n" .. tools.nodes.config.each_indices.arcs( opts.nodes[2] ) ..  " " 
			  .. showtable( redis.call('smembers', tools.nodes.config.each_indices.arcs( opts.nodes[2] ) ) ) 
			)
		
	end
	opts.config = tools.arcs.config
	return tools.arcnode.create( opts )
end

tools.arcs.delete = function ( opts )
	type_assert( opts, "table")
	type_assert( opts.id, "nil", nil, true)
	return tools.arcnode.delete( { id=opts.id, config=tools.arcs.config } )
end

tools.nodes = {}

tools.nodes.config = { 
	name="nodes",
	index="nodes",
	each_indices = { 
		arcs=function (id) assert( not ( id == nil ), "id Cannot be NIL".. debug.traceback()  ); return "nodes_"..id.."_arcs" end
	},
	each_templates= {
		id={ 
			genname=function (id) return "nodes_"..id end,
			attributes={ }
		}
	}
}

tools.nodes.exists = function ( opts )
	assert( type(opts) == 'table', "tools.nodes.exists: opts must be table" )
	type_assert( opts['id'], 'nil', nil, true )
	return tools.index.exists( { index=tools.nodes.config.index , value=opts['id'] } )
end

tools.nodes.create = function ( opts )
	assert( type(opts) == 'table', 
		"tools.nodes.create: opts must be table" )
	opts.config = tools.nodes.config
	return tools.arcnode.create( opts )
end

tools.nodes.delete = function ( opts )
	type_assert( opts, "table")
	type_assert( opts.id, "nil", nil, true)
	for i,v in pairs( redis.call( "SMEMBERS", tools.nodes.config.each_indices.arcs(opts.id)  ) ) do
		assert( not( tools.arcs.exists( {id=v}) ), 
			"Cannot delete node " .. opts.id .. " : connected by arc " .. v )
	end
	return tools.arcnode.delete( { id=opts.id, config=tools.nodes.config } )
end
