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

	def exception_json e, msg = "", s=500
		status s
		content_type "application/json"
		j=JSON.pretty_generate "exception" => {
				"type" => e.class.name,
				"message" => e.message.to_s,
				"backtrace" => e.backtrace.to_a,
			},
			"message" => msg.to_s
		$stderr.puts j
		return j
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

	def list_erb itemset, sf, subtitle=nil
		if js 
			itemset.to_h
		else
			erb :list, :locals=>{:items=>itemset,:sf=>sf}
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

def class_by_param param, type = ItemSet
	c = Object.const_get( cname = param.capitalize )
	raise TypeError.new( "Invalid set #{param} (converted to #{cname})"
			) unless c.kind_of? Class and c < type
	c
end

def obj_by_param param, type = Item
	c = Object.const_get( cname = param.gsub(/s$/, '' ).capitalize )
	raise TypeError.new( "Invalid object #{param} (converted to #{cname})"
			) unless c.kind_of? Class and c < type
	c
end

def start_and_finish cstart, cfinish, preurl
	start = 0
	span=9
	finish = start + span
	if cstart and cstart.to_i 
		start = cstart.to_i
		finish = start + span
		s=true
	end
	if cfinish and cfinish.to_i and cfinish.to_i <= finish
		finish = cfinish.to_i
		f=true
	end
	preurl = "#{preurl}/" unless %r:/$: =~ preurl
	suburl="#{start},#{finish}"
	unless s and f # unless used captured (param) start and finish
		return :status=>303, :url=>"#{preurl}/#{suburl}", :suburl=>suburl, :preurl=>preurl, :start=>start,:finish=>finish
	end
	return :status=>200, :start=>start,:finish=>finish, :preurl=>preurl, :suburl=>suburl
end

# view any viewable or subset
get %r:^/([a-z]+)/(\d+)(/([a-z]+)(/(\d+),((\d+)/?)?)?)?$: do
	ctype = 0
	cid   = 1
	csub = 3 
	cstart=5
	cfinish=7
	begin 
		c = obj_by_param params[:captures][ctype]
		id = params[:captures][cid].to_i
		n = c.new id
		# if a subgroup, we need to handle paging there
		if params[:captures][csub]
			sub = params[:captures][csub]
			preurl="/#{params[:captures][ctype]}/#{id}/#{sub}"
			raise Exception.new "No such parameter: sub" unless n[sub]
			raise TypeError.new( "parameter #{sub} is not listable ( unimplemented" 
				) unless n[sub].kind_of? ItemSet
			sf = start_and_finish params[:captures][cstart], params[:captures][cfinish], preurl
			if sf[:status] == 303
				redirect "/#{params[:captures][ctype]}/#{id}/"+
					"#{params[:captures][csub]}/#{sf[:suburl]}", 303
			else
				erb = erb(:list, :locals=>{ 
						:items=>n[sub].loadSome(sf[:start], sf[:finish]),
						:sf=>sf
				})
			end
		# no subgroup; we just apply 
		else
			erb = (js ? n.to_h : item_erb(n) )
		end
		main_erb erb 
	rescue Exception=>e
		status 404
		exception_json( e, "Could not create class and view id #{id} of #{c.inspect}", 404 )
	end
end

# view any viewable set
get %r{^/([a-z]+)(/((\d+),(\d+)?/?)?)?$} do
	ctype = 0
	cstart = 3
	cfinish = 4
	begin 
		captures = params[:captures]
		c = class_by_param params[:captures][ctype]
		sf = start_and_finish captures[cstart], captures[cfinish], "/#{captures[ctype]}"
		if sf[:status] == 303
			url="/#{captures[ctype]}/#{sf[:suburl]}"
			redirect url, 303
		else	
			main_erb erb( :list, :locals => { :items=>c.new.loadSome( sf[:start],sf[:finish] ), :sf=>sf} )
		end
	rescue Exception=>e
		status 404
		exception_json( e, "Could not create class and view of #{c.inspect}", 404 )
	end
end

get "/" do
	main_erb erb( 
		:index, 
		:locals => {
			:arcs =>   list_erb( Arcs.new.loadSome( 0, 9), start_and_finish(0,9, "/arcs/")),
			:nodes =>  list_erb( Nodes.new.loadSome( 0, 10), start_and_finish(0,10, "/nodes/")) 
		}
	)
end

get "/*" do 
	main_erb erb404
end



