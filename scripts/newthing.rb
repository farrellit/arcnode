require 'redis'
require 'colorize'

r = Redis.new 
r.select 1

num = 1
if ARGV[0].to_i > 0
	num = ARGV[0].to_i 
end


things_create = r['things.create']

num.times do 

# find extant node
nodecount = r.zcard 'nodes'
node=0
until r.zrank 'nodes', node
	node = rand(nodecount)+1
end
puts "Creating on node " + node.to_s.yellow

thing=r.evalsha things_create, [], [node]
puts "Thing #{thing.to_s.green} created"

end
