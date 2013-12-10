require "rubygems"
require "erubis"
require "redis"
require "logger"
require "colorize"

$r = Redis.new
$r.select 1

$log = Logger.new $stderr
$log.level = Logger::DEBUG


class Pathable 
	
	attr_reader :id
	
	def loaded? 
		return @loaded
	end
	
	def self.setName 
		"#{self.name.downcase}".gsub( /([^s])$/, "\\1s" )
	end

	def path= p
		@path = p.to_a
	end
	
	# classes have standard subdir ./arcs ./nodes etc
	def self.path 
		self.genpath
	end

	def self.genpath
		[ self ]
	end

	def path 
		if @path 
			@path + [ self ]
		else
			genpath
		end
	end
	
	def genpath 
		a = [ self.class ]
		a << self if @id
		return a
	end

	def self.url_component
		# return a url for the _class_
		"#{self.setName}"
	end

	def url_component
		@url_component || @id || self.class.setName
	end
	
	def self.text_component
		self.setName
	end

	def text_component
		@id || self.class.text_component
	end

	# combine the path to a url for this resource (set or item)
	def self.path_url forpath=nil
		urls=[]
		forpath=path unless forpath
		forpath.each do |p|
			urls << p.url_component.to_s if p.url_component and p.url_component.to_s.length > 0
		end
		"/" + urls.join( "/" )
	end

	def path_url
		self.class.path_url path()
	end

	def self.path_html path 
		urls= [ ]
		path.each do |p|
			break unless p; # nil elements break the chain
			if p.kind_of?(Class) and p <= Pathable
				urls << " <a class='Class #{p.name}' href='#{p.path_url}'>#{p.text_component}</a> "
			elsif p.kind_of? Pathable
				urls << " <a class='Instance #{p.class.name}' href='#{p.path_url}'>#{ p.text_component }</a> "
			else
				urls << "<div class='Unknown'>Inspect: <code>" + Rack::Utils.escape_html(p.inspect) + "</code> <code><b>#{p.class.name}</b></code></div>"
			end
		end
		" <a class='indexlink' href='/'>/</a> #{urls.join "/" }"
	end

	def path_html 
		self.class.path_html path()
	end

	def inspect 
		Rack::Utils.escape_html( super )
	end
end

class Item < Pathable # Node or Arc
	
	def initialize id
		@loaded = false
		@data = [] 
		load_data id
	end
	
	def load_data id
		if $r.sismember self.class.setName, id
			@id = id
			@data = $r.hgetall get_data_key
		else
			@loaded = false 
			@id = nil
			@data = {}
			raise "#{self.class.name}::#{__method__}: 
				#{id} is not a member of #{self.class.setName}"
		end
		return @loaded = true
	end

	def [] param
		@data[param]
	end

	def to_h 
		return @data
	end

	def param_smembers key, redis_key, type
		itemset = type.new
		itemset.set_name = redis_key
		itemset.path = self.path 
		itemset.loadAll
		@data[key] = itemset
	end
	def get_data_key 
		return "#{self.class.setName}_#{@id||'unbound'}"
	end

	def link_url
		path_url
	end

	def link_text 
		"<a class='#{self.class.name} Instance' href='#{link_url}'><b>#{self.class.name} id #{@id}</b></a> #{link_extra}"
	end
	def link_extra 
		"<small><code>#{ Rack::Utils.escape_html(self.inspect)}"
	end
end

class Node < Item
	def link_extra
		arcs = ""
		acount = 0
		@data['arcs'].each{ |id,arc| 
			arcs << " <a class='Arc' href='#{arc.link_url}'>#{id}</a>"
			acount += 1
			if acount > 9 and acount < ( @data['arcs'].count - 1 )
				arcs << "<a href='#{@data['arcs'].path_url}' class='Arcs'>&hellip;</a> "
				break
			end 
		}
		"Connected by <a class='Arc' href='#{@data['arcs'].path_url}'>#{@data['arcs'].count} Arcs</a>: #{arcs}"
	end
	def load_data id
		super
		param_smembers "arcs", "nodes_#{@id}_arcs", Arcs
	end
end

class Arc < Item
	def link_extra
		nodes = ""
		@data['nodes'].each{ |id,node| nodes << " <a href='#{node.link_url}'>#{id}</a> " }
		"Connecting Nodes: #{nodes}"
	end
	def load_data id
		super
		param_smembers "nodes", "arcs_#{@id}_nodes", Nodes
	end


end


class ItemSet  < Pathable  #Nodes or Arcs
	
	attr_accessor :set_name, :subtitle
	def initialize type
		@type = type
		@set = [ ]
		@set_name = @type.setName
		@subtitle = self.class.name
	end
	
	def url_component
		return @type.setName()
	end

	def to_h 
		h = {}
		@set.each do |id|
			h[id] = @type.new( id) 
		end
	end

	def each_key
		@set.each do |id|
			yield id
		end
	end
		

	def each 
		@set.each do |id|
			yield id, @type.new( id )
		end
	end
	
	def << obj
		return add obj
	end	

	def add obj
		obj = obj.id if obj.kind_of? @type
		@set.push obj unless @set.include? obj
	end
	
	def loadAll
		@set.clear
		$r.smembers( @set_name ).each do |item_id|
			add item_id
		end
		return self
	end

	def count
		return @set.count
	end

end

class Nodes < ItemSet
	def initialize 
		super Node
	end
end

class Arcs < ItemSet
	def initialize 
		super Arc
	end
end


=begin

def get_arcs
	arc_keys = $r.smembers "arcs"
	arcs={}
	arc_keys.each do |id|
		arcs[id] = $r.hgetall "arcs_#{id}"
		arcs[id]['nodes'] = $r.smembers "arcs_#{id}_nodes"
	end
	arcs
end

def get_nodes
	node_keys = $r.smembers "nodes"
	nodes={}
	node_keys.each do |id|
		nodes[id] = $r.hgetall "nodes_#{id}"
		nodes[id]['arcs'] = $r.smembers "nodes_#{id}_arcs"
	end
	nodes
end

=end
