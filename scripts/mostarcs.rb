require 'redis'
require 'thread'
require 'colorize' 
require 'json' 

class Timer

	attr_accessor :loud

	def initialize msg=nil, loud=false
		@marks = []
		@t=nil
		@sum=0.0
		@loud = loud
		mark(msg) if msg 
	end

	def mark msg
		m = { :time=>Time.new.to_f, :msg => msg.to_s }
		count m
		@marks << m
		report_mark(m) if @loud
	end

	def << msg
		return mark msg
	end

	def count m
		if @t
			@sum += m[:time] - @t 
		else
			@t = m[:time]
			@sum = 0
		end
	end

	def recount 
		@t=nil
		@sum=0.0
		@marks.each do |m|
			count m
			report_mark m
		end
	end

	def report_mark m
		printf "\033[1;31mT=\033[0m%6.3f (+ %6.3f) %s\n", @sum, m[:time] - @t, m[:msg]
	end

	
end

times = Timer.new "Program Starts", true

r=Redis.new
r.select 1

class Most
	attr_reader :most, :nodes
	def most
		m = ""
		@mutex.synchronize { m = @most } 
		return m
	end
	def nodes
		n=[]
		@mutex.synchronize { n = @nodes.dup } 
		return n
	end	
	def initialize
		@mutex = Mutex.new
		@most, @count, @avg, @sum = 0, 0, nil, 0
		@nodes = []
	end
	def consider node, num
		@mutex.synchronize {
			num = num.to_i
			@count += 1
			@sum += num
			@avg = @sum.to_f/@count.to_f
			if num>@most
				@most=num
				@nodes=[node]
			elsif num ==@most
				@nodes << node
			end
			@most
		}
	end
	def stats 
		return { :most=>@most, :nodes=>@nodes.dup, :avg=>@avg, :count => @count,:sum => @sum }
	end
end

m = Most.new
r.smembers( 'nodes' ).each do |node| 
	m.consider node, r.scard("nodes_#{node}_arcs")
end

times << "Found node(s) with the most arcs - nodes #{ m.nodes.map{|n| "http://localhost:4567/nodes/#{n}" }.join ","} have #{m.most}: #{ m.stats.to_json}"

