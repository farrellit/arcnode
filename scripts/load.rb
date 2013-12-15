require 'redis'
require 'digest'
require 'colorize' 

r = Redis.new
r.select 1

lib= File.read 'lib.lua'

`find ./ -iname '*lua' -and -not -iname 'lib.lua'`.each_line do |file|
	file.strip!
	name = file.gsub( /\.(lua|\/)/, '' ).gsub('/', '.')
	script = "#{lib}\n#{File.read file}"
	File.open "#{file}.txt", "w" do |f|
		f.write script
	end
	mysha = Digest::SHA1.new.hexdigest script
	puts "file #{file.bold.yellow } |  script #{name.bold} My SHA: #{mysha.bold}"
	puts "ref #{ "#{file}.txt".green }"
	begin
		puts "Redis: " + r[name] = r.script( :load, script )
	rescue Exception => e
		puts "Error in Script".bold.red
		IO.popen( 'nl', 'w+' ) { |f| 
			f.write script 
			f.close_write
			puts f.read.red
		}
		puts "Error in #{file.bold}: #{e.class.name}: #{e.message} \n#{e.backtrace.join "\n\t"}"
		exit(-1)
	end	
end


