require 'open3'
require 'tempfile'
require 'ostruct'
require 'fileutils'


class Squeezem
  def initialize(options)
    @options = options
    find_helpers
    @total_bytes = 0
    @saved_bytes = 0
    @files_seen = 0
    @files_ignored = 0
    @files_with_saving = 0
    output_dir = make_output_dir
    at_exit do
      write_cache
      FileUtils.rm_rf(output_dir)
    end
    @output_path = File.join(output_dir, 'x')
    @files = read_cache
    trap("INT") {
      summary
      exit
    }
  end

  def find_helpers
    @helpers = {}
    @helpers[:png] = 1 if command_exists?("pngcrush")
    @helpers[:jpg] = 1 if command_exists?("jpegtran")
    if @helpers.size == 0
      $stderr.puts "Can't find any helpers - please install at least one of pngcrush or jpegtran!"
      exit 1
    end
  end

  def command_exists?(command)
    system("which #{command} >/dev/null 2>/dev/null")
    return false if $?.exitstatus == 127
    return true
  end

  def make_output_dir
    begin
      Dir.mktmpdir
    rescue NoMethodError
      # Lame fallback for 1.8.6-p369 and below
      dir = Dir.tmpdir + "/squeezem-#{$$}"
      Dir.mkdir(dir)
      FileUtils.chmod(0700, dir)
      return dir
    end
  end

  def squeeze(path)
    log("Considering #{path}")
    file_type = get_file_type(path)
    unless valid_file_type?(file_type)
      log("Ignoring, #{file_type} not a valid file type")
      @files_ignored += 1
      return
    end
    @files_seen += 1
    @path = path
    @size = File.size(path)
    log("File size #{@size}")
    canonical_path = File.expand_path(path)
    unless @options.ignorecache
      cache = @files[canonical_path]
      log("Read cache #{cache}")
      if cache && cache.size == @size
        unless @options.squeezem && cache.saving > 0
          log("Skipping file, already processed")
          record_saving(cache.saving)
          return
        end
      end
    end
    output = process_file(path, file_type)
    if File.exist?(@output_path)
      new_size = File.size(@output_path)
      if new_size == 0
        report_error(path, output)
        return
      end
      saving = @size - new_size
      record_saving(saving)
      keep_or_remove_output
      if @options.squeezem
        cache_saving = 0
        cache_size = new_size
      else
        cache_saving = saving
        cache_size = @size
      end
      @files[canonical_path] = OpenStruct.new(:size => cache_size, :saving => cache_saving)
    else
      report_error(path, output)
    end
  end

  def report_error(path, output)
    $stderr.print "Error processing #{path}"
    $stderr.puts ": #{output}" if output
  end

  def get_file_type(path)
    extension = File.extname(path).sub('.', '')
    if extension.empty?
      return nil
    else
      return extension.to_sym
    end
  end

  def valid_file_type?(type)
    @helpers[type]
  end

  def process_file(path, file_type)
    output = ''
    case file_type
    when :png
      cmd = ['pngcrush', '-quiet', '-rem', 'allb', path, @output_path]
      log("Calling #{cmd.join(' ')}")
      Open3.popen3(*cmd) do |stdin, stdout, stderr|
        output = stdout.read
        output += stderr.read
      end
    when :jpg
      File.open(@output_path, "w") do |out|
        cmd = ['jpegtran', '-copy', 'none', '-optimize', '-perfect', path]
        log("Calling #{cmd.join(' ')}")
        Open3.popen3(*cmd) do |stdin, stdout, stderr|
          out.write(stdout.read)
          output = stderr.read
        end
      end
    end
    return output
  end

  def keep_or_remove_output
    if @options.squeezem
      FileUtils.mv(@output_path, @path)
    else
      File.unlink(@output_path)
    end
  end

  def record_saving(saving)
    if saving > 0
      @saved_bytes += saving
      @total_bytes += @size
      @files_with_saving += 1
      puts @path
    end
  end

  def summary
    return unless @files_with_saving > 0
    if @total_bytes > 0
      pct_saved = @saved_bytes * 100.0 / @total_bytes
    else
      pct_saved = 0
    end
    could_save_or_saved = @options.squeezem ? 'saved' : 'could save'
    puts "#{@files_with_saving} files out of #{@files_seen} #{could_save_or_saved} #{@saved_bytes} out of #{@total_bytes} (%.2f)%%. #{@files_ignored} files ignored." % pct_saved
  end

  def cache_filename
    File.expand_path("~/.squeezem-cache")
  end

  def read_cache
    begin
      return Marshal.load(File.read(cache_filename))
    rescue
      return {}
    end
  end

  def write_cache
    File.open(cache_filename, "w") do |f|
      f.puts Marshal.dump(@files)
    end
  end

  def log(message)
    puts message if @options.verbose
  end
end
