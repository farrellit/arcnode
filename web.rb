#!/usr/bin/ruby
#
require 'rubygems'
require 'sinatra'
require 'json'
require './lib/arcnode.rb' 

helpers do
	def h(text)
		Rack::Utils.escape_html(text)
	end
	def js
		return request.accept? "application/json"
	end

	def exception_json e, msg = ""
		status 500
		JSON.pretty_generate	 Hash.new( 
			"exception" => {
				"type" => e.class.name,
				"message" => e.message.to_s,
				"backtrace" => e.backtrace.to_a,
			},
			"message" => msg.to_s
		)
	end
	def main_erb body 
		if js 
			begin 
				JSON.pretty_generate body
			rescue Exception => e
				exception_json e, 
					"#{__method__}: Request type was application/json, "+
					"but failed to parse the json body: #{body.inspect}"
			end
		else
			erb :main, :locals => { :body => body }
		end
	end

	def list_erb itemset, subtitle=nil
		if js 
			itemset.to_h
		else
			erb :list, :locals=>{:items=>itemset}
		end
	end
	def erb404 
		erb :error404 
	end

	def item_erb id, type=nil , subtitle=nil  #pass obj or id,type
		unless type
			unless id.kind_of? Item 
				raise "if passing no type to #{__method__}, first arg must be an Item"
			end
			type = id.class # use type from passed item
		end
		if id.kind_of? type
			item = id
		else # could be more intellegent; try to coerce to string or valid ID
			item = type.new id
		end
		status 404 unless item.loaded? 
		if js 
			item.to_h
		else
			erb( :item, :locals=>{ :id=>params[:id], :item => item, :subtitle=>subtitle } )
		end
	end
end



get "/nodes/:id/arcs" do
	n = Node.new(params[:id])
	if n.loaded?
		main_erb list_erb( js ? n['arcs'].to_h : n['arcs'] )
	else
		status 404
		main_erb( item_erb( js ? n.to_h : n ) )
	end
end

get "/nodes/:id/things" do
	n = Node.new(params[:id])
	if n.loaded?
		main_erb list_erb( js ? n['things'].to_h : n['things'] )
	else
		status 404
		main_erb( item_erb( js ? n.to_h : n ) )
	end
end

put "/arcs/:id/transfer/:thing" do
	r = Redis.new
	r.select 1
	sha=r['things.move']
	begin
		newnode = r.evalsha sha, [], [ params[:thing].to_i, params[:id].to_i ]
		redirect "/nodes/#{newnode}", 303
		"Thing moved to node #{newnode}"
	rescue Exception=>e 
		status 500
		"#{e.class.name}: #{e.message}.  #{e.backtrace.join ", " } "
	end
end

get "/arcs/:id/nodes" do
	n = Arc.new(params[:id])
	if n.loaded?
		main_erb list_erb( js ? n['nodes'].to_h : n['nodes'] )
	else
		status 404
		main_erb( item_erb( js ? n.to_h : n ) )
	end
end

get "/nodes/:id" do
	main_erb item_erb(params[:id], Node)
end

get "/nodes" do
	main_erb list_erb(Nodes.new.loadAll)
end

get "/arcs/:id" do
	main_erb item_erb(params[:id], Arc)
end

get "/arcs" do
	main_erb erb( :list, :locals => { :items=>Arcs.new.loadAll } )
end

get "/things/:id/nodes" do
	n = Thing.new(params[:id])
	if n.loaded?
		main_erb list_erb( js ? n['nodes'].to_h : n['nodes'] )
	else
		status 404
		main_erb( item_erb( js ? n.to_h : n ) )
	end
end
get %r{/things/(\d+)$} do
	id = params[:captures][0]
	main_erb item_erb(id, Thing)
end

get %r{/things(/(\d+),(\d+)?)?} do
	content_type "application/json"
	JSON.pretty_generate :captures=>params[:captures] , :request=>request.inspect
	# main_erb erb( :list, :locals => { :items=>Things.new.loadSome } )
end

get "/" do
	main_erb erb( 
		:index, 
		:locals => {
			:arcs =>   list_erb( Arcs.new.loadAll) ,
			:nodes =>  list_erb( Nodes.new.loadAll) 
		}
	)
end

get "/*" do 
	main_erb erb404
end



