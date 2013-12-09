
require './lib.rb'
require 'colorize'

puts (arcs = get_arcs).inspect.to_s.green

puts (nodes = get_nodes).inspect.to_s.green

puts 
13.times { print "|".red }

puts " \n"


[ Arcs.new, Nodes.new ].each do |t|
	puts t.loadAll.inspect.green
	t.each do |item|
		puts item.inspect
	end
end
