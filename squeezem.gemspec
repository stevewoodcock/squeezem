Gem::Specification.new do |s|
  s.name        = "squeezem"
  s.version     = "0.1.1"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Steve Woodcock"]
  s.email       = ["steve.woodcock@gmail.com"]
  s.homepage    = "http://github.com/stevewoodcock/squeezem"
  s.summary     = "List pngs which are bigger than they need to be, and optionally compress them"
  s.description = "List pngs which are bigger than they need to be. Can optionally
compress them, but is designed mainly to keep an eye on a tree of
images to make sure they stay in good shape."
 
  s.rubyforge_project         = "squeezem"
 
  s.files        = Dir.glob("{bin,lib}/**/*") + %w(LICENSE README)
  s.executables  = ['squeezem']
  s.require_path = 'lib'
end
