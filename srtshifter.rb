
require 'optparse'





class CustomTime

	attr_reader :hours, :minutes, :seconds, :millis

	def initialize(hours, minutes, seconds, millis)
		@hours = hours.to_i
		@minutes = minutes.to_i
		@seconds = seconds.to_i
		@millis = millis.to_i
	end


	# Get full time in milliseconds
	def to_millis
		return @millis + @seconds * 1000 + @minutes * 60000 + @hours * 3600000
	end


	# Shift a CustomTime by a fixed delta
	def shift_fixed(delta, sign)
		uncapped_millis = @millis + (delta.millis * sign)
		extra_seconds = uncapped_millis / 1000

		uncapped_seconds = @seconds + extra_seconds + (delta.seconds * sign)
		extra_minutes = uncapped_seconds / 60

		uncapped_minutes = @minutes + extra_minutes + (delta.minutes * sign)
		extra_hours = uncapped_minutes / 60

		uncapped_hours = @hours + extra_hours + (delta.hours * sign)

		@hours = uncapped_hours
		@minutes = uncapped_minutes % 60
		@seconds = uncapped_seconds % 60
		@millis = uncapped_millis % 1000
	end


	# Shift a CustomTime by a linear-increasing or linear-decreasing delta
	def shift_linear(coefficient)
		new_full_millis = (to_millis() * coefficient).to_i

		@millis = new_full_millis % 1000
		@seconds = (new_full_millis % 60000) / 1000
		@minutes = (new_full_millis % 3600000) / 60000
		@hours = (new_full_millis / 3600000)
	end


	def self.parse(str)
		# Pattern : 00:00:03,151
		arr = str.split(":")
		hours = arr[0]
		minutes = arr[1]

		arr2 = arr[2].split(",")
		seconds = arr2[0]
		millis = arr2[0].match?(/[0-9]{2}\,[0-9]{3}/) ? arr2[1] : 0

		return self.new(hours, minutes, seconds, millis)
	end


	def to_s
		return "#{'%02d' % @hours}:#{'%02d' % @minutes}:#{'%02d' % @seconds},#{'%03d' % @millis}"
	end

end





class SrtBlock

	attr_reader :id, :t_start, :t_end, :text
	
	def initialize(id, t_start, t_end, text)
		@id = id
		@t_start = t_start
		@t_end = t_end
		@text = text
	end


	# Change the speed of the SubBlock
	# source_framerate is the framerate the subtitles were made for
	# 	(ex : 25 FPS for European videos)
	# target_framerate is the framerate of the video you want to sync the subtitles for
	# 	(ex : 23.976 FPS for U.S videos)
	def edit_framerate(source_framerate, target_framerate)
		coefficient = source_framerate.to_f / target_framerate.to_f
		@t_start.shift_linear(coefficient)
		@t_end.shift_linear(coefficient)
	end
	alias_method :shift_linear, :edit_framerate


	def shift_fixed(delta, positive)
		@t_start.shift_fixed(delta, positive)
		@t_end.shift_fixed(delta, positive)
	end


	# Parse a SRT timing line into a SrtBlock instance. Syntax :
	# 00:00:01,492 --> 00:00:03,151
	def self.parse(lines)
		id = lines[0].to_i
		spl = lines[1].split(" --> ")
		t_start = CustomTime.parse(spl[0])
		t_end = CustomTime.parse(spl[1])
		text = lines[2..-1]

		return self.new(id, t_start, t_end, text)
	end


	def to_s
		return [@id, "#{@t_start} --> #{@t_end}", @text.join("\n")].join("\n")
	end


end





class SrtFile

	attr_reader :file, :blocks, :lines, :basename

	def initialize(filename)
		@file = File.new(filename)
		@basename = File.basename(@file.path)
		@lines = IO.readlines(filename)
		@blocks = parse()
	end

	def parse()
		blocks = []
		stack = []

		@lines.each do | line |
			unless line.chomp.empty?
				stack << line.chomp
				next
			end
			blocks << SrtBlock.parse(stack)
			stack = []
		end

		return blocks
	end


	def edit_framerate(source_framerate, target_framerate)
		@blocks.each do | block |
			block.shift_linear(source_framerate, target_framerate)
		end
	end
	alias_method :shift_linear, :edit_framerate


	def shift_fixed(delta, positive)
		@blocks.each do | block |
			block.shift_fixed(delta, positive)
		end
	end


	def write(output_path)
		f = File.new(output_path, "w")
		f.write(self.to_s)
		f.close()
		return output_path
	end


	def to_s()
		ret = []
		@blocks.each do | block |
			ret << block.to_s
		end
		return ret.join("\n\n")
	end

end





options = {
	:fixed => {
		:sign => nil,
		:delta => nil
	},
	:linear => {
		:source => nil,
		:target => nil
	},
	:output => nil
}

ARGV.options do | opts |

	opts.banner = "Usage: srtshifter.rb -o OUTPUT_FILE [options] file ..."

	opts.on("-f", "--fixed-shift DELTA", "Shift by a fixed delta. Pattern : '-00:00:03,150' (+ to delay, - to advance)", String) do | val |
		#TODO : regex to check val
		spl = val.split(":")
		sign = val[0] == "-" ? -1 : +1
		options[:fixed][:sign] = sign
		spl[0] = spl[0].to_i.abs.to_s
		options[:fixed][:delta] = CustomTime.parse(spl.join(":"))
	end

	opts.on("-l", "--linear-shift SOURCE_FRAMERATE/TARGET_FRAMERATE", "Shift by a linear increasing/decreasing delta. (Ex: '25/23.976')", String) do | val |
		#TODO : regex to check val
		#TODO : remove -l, replace with both -s & -t
		split = val.split("/")
		options[:linear][:source] = split[0].to_f
		options[:linear][:target] = split[1].to_f
	end

	opts.on("-o", "--output-file FILE", "Output file. Existing files will be overwritten. If not specified, '_resynced' will be appended to the filename", String) do | val |
		val = val[0...-1] if val[-1] == "/"
		val = val.gsub("\\", "/") # For Windows paths
		options[:output] = File.path(val) # TODO : useless
	end

	opts.parse!
end






if ARGV.length == 0
	puts "No file specified. See --help for syntax"
	exit 1
end

#
# ARGV.each do | arg |
#

arg = ARGV[0].gsub("\\", "/")
if options[:output].nil?
	synced_name = arg.split(".srt")[0] + "_resynced.srt"
	options[:output] = File.path(synced_name)
end

puts "Processing : '#{arg}'"

srt = SrtFile.new(arg)

puts "\tParsed (#{srt.blocks.length} blocks)"

# Apply linear shift
unless options[:linear][:source].nil? || options[:linear][:target].nil?
	srt.shift_linear(options[:linear][:source], options[:linear][:target])
	puts "\tLinear shifting"
end

unless options[:fixed][:sign].nil? || options[:fixed][:delta].nil?
	srt.shift_fixed(options[:fixed][:delta], options[:fixed][:sign])
	puts "\tFixed shifting"
end

puts "#{options[:output]}"
output_path = srt.write(options[:output])

puts "\tWritten to : '#{output_path}'"

#
# end
#
