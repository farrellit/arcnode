require 'redis'
require 'thread'
require 'colorize' 
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

r.flushall
r.select 1

system("ruby ./load.rb")

times <<  "Flushed and Loaded"

sha=r['nodes.create']
puts "'nodes.create': #{sha}"
n=10240

(1..n).each do |i|
	r.evalsha sha
end

times << "created #{n} nodes"



sha=r['arcs.create'] 
n.times do | i |
	begin
		r.evalsha sha, [], [ "#{rand(n)+1}", "#{rand(n)+1}" ]
	rescue Exception=>e
		$stderr.puts e.message
	end
end

times << "created #{n} arcs"

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
		@nodes = []
	end
	def consider node, num
		@mutex.synchronize {
			@most = 0
			num = num.to_i
			if num>@most
				@most=num
				@nodes=[node]
			elsif num ==@most
				@nodes << node
			end
			@most
		}
	end
end


m = Most.new
r.smembers( 'nodes' ).each do |node| 
	m.consider node, r.scard("nodes_#{node}_arcs")
end



times << "Found node(s) with the most arcs - nodes #{ m.nodes.map{|n| "http://localhost:4567/nodes/#{n}" }.join ","} have #{m.most}"
nodes_delete =r['nodes.delete']
all = r.scard 'nodes'
removed=0
threads = []
maxthreads=100
thread_timeout=0.01
dojoin=Proc.new do |continue| # continue = cleans up all threads
	threads.each do |th|	
		unless th.alive?
			threads.delete th
			next
		end
		if th.join( thread_timeout )
			$stderr.puts th['stdout'].green
			$stderr.puts th['stderr'].red
			threads.delete th
			break unless continue
		end
	end
end
joinall=Proc.new do 
	while threads.count > 0 do 
		dojoin[true]
	end
end

m = Most.new
r.smembers( 'nodes' ).each do |node| 
	dojoin[false] while threads.count >= maxthreads # need to let some threads die off
	threads << Thread.new do
	begin
		Thread.current['stderr'] = ""
		Thread.current['stdout'] = ""
		rn = Redis.new :host=>"127.0.0.1", :port=>( 6379 + rand(4) )
		m.consider node, rn.scard("nodes_#{node}_arcs")
	rescue Exception=>e
		Thread.current['stderr'] << e.message
	end
	end
end

joinall[]

times << "Found node(s) with the most arcs - nodes #{ m.nodes.map{|n| "http://localhost:4567/nodes/#{n}" }.join ","} have #{m.most}\nthis time, threaded."

r.smembers( 'nodes' ).each do |node|
	dojoin[false] while threads.count >= maxthreads # need to let some threads die off
	threads << Thread.new do 
	begin
			Thread.current['stderr'] = ""
			Thread.current['stdout'] = ""
			r.evalsha nodes_delete, [], [  node ]
			Thread.current['stdout'] << "Deleted #{node}"
			removed+=1
	rescue Exception=>e
		Thread.current['stderr'] << e.message
	end
	end
end

joinall[]

#times.loud=false
#
times << "Deleted #{removed} ( of #{all} ) arcless nodes successfully - #{maxthreads} (or less) at a time!"
puts
puts
puts
times.recount
