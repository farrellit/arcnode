local function log (msg) 
	redis.log( redis.LOG_NOTICE, msg )
end
local function notice (msg) 
	redis.log( redis.LOG_NOTICE, debug.traceback() .. "\n" .. msg )
end

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

tools.logdel =function( key ) 
	log( "delete " .. key )
	redis.call( "DEL",  key )
end

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
			notice( "\"Unused\" ID ".. i  .. " from " .. opts['counter'] 
				.. " already existed in " .. opts['index'] 
				.. " : choosing another " )
			i = 0
		end
	end
	return i
end

-- should be used with caution on large indexes.
tools.index.all = function( opts )
	type_assert( opts, 'table' )
	type_assert( opts.index, 'nil', nil, true )
	return redis.call('ZRANGE', opts.index, 0, -1 )
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
	log( "index.add: adding " .. opts['value'] .. " to " .. opts['index'])
	local resp = redis.call( 'ZADD', opts['index'], tonumber(opts['value']), opts['value'] )
	return resp
end

tools.index.exists = function ( opts ) 
	assert( type(opts) == 'table', "tools.index.exists - opts must be of type table " .. debug.traceback() ) 
	assert( not(type(opts['index']) == "nil"), "opts['index'] must be defined" )
	assert( not(type(opts['value']) ==  "nil"), "opts['value'] must be defined" )
	local ret = true
	local resp = redis.call( "ZRANK", opts['index'], opts['value'] ) 
	if not resp then
		ret = false
	end
	return ret
end	

tools.index.del = function ( opts )
	assert( type(opts) == 'table', "tools.index.del - opts must be of type table " .. debug.traceback() ) 
	assert( not(type(opts['index']) == "nil"), "opts['index'] must be defined" )
	assert( not(type(opts['value']) ==  "nil"), "opts['value'] must be defined" )
	log( "Removing  ".. opts['value'].. " from " .. opts['index'] )
	local res = tonumber( redis.call( "ZREM", opts['index'], opts['value'] ) )
	log( "OK, removed")
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
	log( "tools.index.cross : crossing: " .. showtable( opts )) 
	redis.call( 'ZADD', opts[1]['index'], tonumber(opts[2]['value'] ), opts[2]['value'] )
	redis.call( 'ZADD', opts[2]['index'], tonumber(opts[1]['value'] ), opts[1]['value'] ) 
	return true
end

tools.index.uncross = function ( opts ) 
	assert( type(opts) == 'table', "tools.index.uncross - opts must be of type table " .. debug.traceback() ) 
	for i in pairs({ 1, 2 }) do
		assert( type(opts[i]) == "table", "opts["..i.."] must be of type table"  )
		assert( not(type(opts[i]['index']) == "nil"), "opts["..i.."]['index'] must be of type string" )
		assert( not(type(opts[i]['value']) ==  "nil"), "opts["..i.."]['value'] must be of type string" )
	end
	log( "tools.index.cross : uncrossing: " .. showtable( opts ) ) 
	redis.call( 'ZREM', opts[1]['index'], opts[2]['value'] )
	redis.call( 'ZREM', opts[2]['index'], opts[1]['value'] )
	return true
end

tools.arcnode = {}


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
		if( type( opts[rel] ) == 'table' ) then 
			for i,other in pairs( opts[rel] ) do 
				tools.index.cross( { 
					{ index=ifunc(id), value=id },
					{ index=tools[rel].config.each_indices[config.name](other), value=other }
				} )
			end
		end
	end
	tools.index.add( { index=config.index, value=id } )
	redis.call( 'HSET', config.each_templates.id.genname( id ), 'id', id)
	return id
end

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
	log( "tools.arcnode.delete: removing from main index " .. opts.config.index )
	tools.index.del( { index=opts.config.index, value=opts.id } )
	for rel,ifunc in pairs( opts.config.each_indices ) do
		for i,other in pairs( tools.index.all( {index=ifunc(opts.id)} ) ) do
			log( "Uncrossing " 
				.. ifunc(opts.id) .. "["..opts.id.."] and " 
				.. tools[rel].config.each_indices[opts.config.name](other) 
				.. "["..other.."]" 
			)
			tools.index.uncross( { 
				{ index=ifunc(opts.id), value=opts.id },
				{ index=tools[rel].config.each_indices[opts.config.name](other), value=other }
			} )
		end
		tools.logdel( ifunc(opts.id) )
	end
	for i,tpl in pairs(opts.config.each_templates) do
		tools.logdel( tpl.genname( opts.id ) )
	end
	return opts.id
end

-- ARCS

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
				count_transfers=0
			}
		}
	}
}

tools.arcs.exists = function ( opts )
	assert( type(opts) == 'table', "tools.arcs.exists: opts must be table" )
	assert( not(type(opts['id']) == 'nil'), "tools.arcs.exists: opts['id'] must be set" )
	return tools.index.exists( { index=tools.arcs.config.index , value=opts['id'] } )
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
	for i,k in pairs( redis.call( 'ZRANGE', tools.nodes.config.each_indices.arcs( opts.nodes[1]), 0, -1 ) ) do
		assert( not redis.call('ZRANK', tools.nodes.config.each_indices.arcs( opts.nodes[2] ), k), 
			" Arc " .. k .. " already joins  " .. 
				showtable(redis.call('ZRANGE', tools.arcs.config.each_indices.nodes( k ),0,-1 ) ) 
			.. " options are: " .. opts.nodes[1] .. " and ".. opts.nodes[2] .. "\n" .. 
			  "found in " .. tools.nodes.config.each_indices.arcs( opts.nodes[1] ) ..  " " 
			  .. showtable(redis.call( 'ZRANGE', tools.nodes.config.each_indices.arcs( opts.nodes[1]),0,-1) )
			  .. " \n and \n" .. tools.nodes.config.each_indices.arcs( opts.nodes[2] ) ..  " " 
			  .. showtable( redis.call('ZRANGE', tools.nodes.config.each_indices.arcs( opts.nodes[2] ),0,-1 ) ) 
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

tools.arcs.transfer = function( opts )
	tools.arcnode.std_assert(opts)
	-- thing exists
	type_assert( opts.thing , 'nil', nil, true )
	assert( tools.things.exists( {id=opts.thing}), "Thing does not exist:" .. opts.thing)
	-- ensure the arc is accessible from the node
	local current_node = tools.things.node( {id=opts.thing} )
	local ismember=redis.call( 
			"ZRANK", 
			tools.nodes.config.each_indices.arcs( current_node ),
			opts.id -- this arc
		)
	redis.log(redis.LOG_NOTICE, "thing " .. opts.thing .." reach arc " .. opts.id .. " from " .. current_node .. "? Answer: " .. tonumber(ismember) )
	assert( ismember,
		"thing " .. opts.thing .." cannot reach arc " .. opts.id
	)
	-- find target node 
	local target_node = nil
	for i,v in pairs( redis.call(
		'ZRANGE', 
		tools.arcs.config.each_indices.nodes( opts.id ),
		0, -1
	) ) do
		if not( v == current_node ) then
			target_node = v
			redis.log( redis.LOG_NOTICE, "found target node " .. i .. " => " .. v  )
		end
	end
	redis.log(redis.LOG_NOTICE, "target node: " .. target_node ) 
	assert(tools.nodes.exists( { id=current_node } ),
		 "No valid target node for thing "..opts.thing 
		.." from node " .. current_node .. " through arc " .. opts.id 
	)
	-- remove from node
	tools.index.uncross(  
		{ 
			{index=tools.things.config.each_indices.nodes(opts.thing),  value = opts.thing},
			{index=tools.nodes.config.each_indices.things( current_node ), value = current_node}
		} 
	)
	-- add to new node
	tools.index.cross(  
		{ 
			{index=tools.things.config.each_indices.nodes(opts.thing),  value = opts.thing},
			{index=tools.nodes.config.each_indices.things( target_node ), value = target_node}
		} 
	)
	-- count trancersals
	local counter = tools.arcs.config.each_templates.id.genname( opts.id )
	redis.call( "HSETNX", counter , 'count_transfers', 0 )
	redis.call( "HINCRBY", counter , 'count_transfers', 1 )
	return target_node
end
	
-- NODES

tools.nodes = {}

tools.nodes.config = { 
	name="nodes",
	index="nodes",
	each_indices = { 
		arcs=function (id) assert( not ( id == nil ), "id Cannot be NIL".. debug.traceback()  ); return "nodes_"..id.."_arcs" end,
		things=function (id) assert( not ( id == nil ), "id Cannot be NIL".. debug.traceback()  ); return "nodes_"..id.."_things" end
	},
	each_templates= {
		id={ 
			genname=function (id) return "nodes_"..id end,
			attributes={ }
		}
	}
}

tools.nodes.exists = function ( opts )
	assert( type(opts) == 'table', "tools.nodes.exists: opts must be table" .. debug.traceback() )
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
	for i,v in pairs( redis.call( "ZRANGE", tools.nodes.config.each_indices.things(opts.id),0,-1 ) ) do
		assert( not( tools.things.exists( {id=v}) ), 
			"Cannot delete node " .. opts.id .. " : inhabited by thing " .. v )
	end
	for i,v in pairs( redis.call( "ZRANGE", tools.nodes.config.each_indices.arcs(opts.id),0,-1  ) ) do
		assert( not( tools.arcs.exists( {id=v}) ), 
			"Cannot delete node " .. opts.id .. " : connected by arc " .. v )
	end
	return tools.arcnode.delete( { id=opts.id, config=tools.nodes.config } )
end

-- THINGS

tools.things = {}
tools.things.config = {
	name="things",
	index="things",
	each_indices = {
		nodes = function( id ) return "things_"..id.."_nodes" end
	},
	each_templates= {
		id={ 
			genname=function (id) return "things_"..id end,
			attributes={ }
		}
	}
}

tools.things.node =function(opts)
	tools.arcnode.std_assert(opts)
	local nodes =redis.call( 
		"ZRANGE",
		tools.things.config.each_indices.nodes( opts.id ), -- node of this thing
		0, -1
	)
	local node 
	for i,v in pairs(nodes) do
		node = v
	end
	return node
end

tools.things.exists = function ( opts )
	assert( type(opts) == 'table', "tools.things.exists: opts must be table" )
	assert( not(type(opts['id']) == 'nil'), "tools.things.exists: opts['id'] must be set" )
	return tools.index.exists( { index=tools.things.config.index , value=opts['id'] } )
end

tools.things.create = function ( opts )
	assert( type(opts) == 'table', 
		"tools.things.create: opts must be table" )
	type_assert( opts.nodes, 'table')
	local c = 0
	for i in pairs(opts.nodes) do c = c + 1 end
	assert( c == 1, "Only one node is allowed per thing when creating nodes; I got " .. c )
	assert(tools.nodes.exists( { id=opts.nodes[0] } ), "node does not exist: " .. opts.nodes[0] )
	opts.config = tools.things.config
	return tools.arcnode.create( opts )
end

tools.things.delete = function ( opts )
	type_assert( opts, "table")
	type_assert( opts.id, "nil", nil, true)
	return tools.arcnode.delete( { id=opts.id, config=tools.things.config } )
end

tools.things.move = function ( opts )
	type_assert( opts, "table")
	type_assert( opts.id, "nil", nil, true)
	type_assert( opts.arc, "nil", nil, true)
	-- arcs must have a chance to process this transaction!
	return tools.arcs.transfer( { id=opts.arc, thing=opts.id} )
end



