# srtshifter

Ruby script to shift timings in a SRT subtitle file

Usage: `srtshifter.rb -o OUTPUT_FILE [options] file ...`

Options:
	
	`-f`, `--fixed-shift DELTA`
	Shift by a fixed delta
	Pattern : `'-00:00:03,150'` (`+` to delay, `-` to advance)

	`-l`, `--linear-shift SOURCE_FRAMERATE/TARGET_FRAMERATE`
	Shift by a linear increasing or decreasing delta
	Ex: `'25/23.976'`

	`-o`, `--output-file FILE`
	Output file. Existing files will be overwritten.
	If not specified, '_resynced' will be appended to the filename