require 'open3'
require 'tempfile'
require 'ostruct'
require 'fileutils'


class Squeezem
  def initialize(options)
    @options = options
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
    return unless valid_file?(path)
    @files_seen += 1
    @path = path
    @size = File.size(path)
    canonical_path = File.expand_path(path)
    unless @options.ignorecache
      cache = @files[canonical_path]
      if cache && cache.size == @size
        unless @options.squeezem && cache.saving > 0
          record_saving(cache.saving)
          return
        end
      end
    end
    output = ''
    Open3.popen3('pngcrush', '-quiet', '-rem', 'alla', '-reduce', '-brute', path, @output_path) do |stdin, stdout, stderr|
      output = stdout.read
    end
    if File.exist?(@output_path)
      new_size = File.size(@output_path)
      if new_size == 0
        $stderr.puts "Empty output for #{path}"
        return
      end
      saving = @size - new_size
      record_saving(saving)
      @files[canonical_path] = OpenStruct.new(:size => @size, :saving => saving)
      keep_or_remove_output
    else
      $stderr.puts "Error processing #{path}:", output
    end
  end

  def valid_file?(path)
    if !(path =~ /\.(png)$/)
      @files_ignored += 1
      return false
    end
    return true
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
end
