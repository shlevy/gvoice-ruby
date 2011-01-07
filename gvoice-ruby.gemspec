# -*- encoding: utf-8 -*-
$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'gvoice-ruby/version'

Gem::Specification.new do |s|
  s.name        = "harleytt-gvoice-ruby"
  s.version     = GvoiceRuby::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Keith Gautreaux", "Roy Kolak", "Jeremy Stephens"]
  s.email       = ["keith.gautreaux@gmail.com"]
  s.homepage    = "http://github.com/kgautreaux/gvoice-ruby"
  s.summary     = "gvoice-ruby is a library for interacting with Google’s Voice service (previously GrandCentral) using ruby."
  s.description = <<-EOS
  gvoice-ruby is currently a very preliminary project with limited functionality basically confined to returning arrays of voicemail or sms objects and sending sms messages, or connecting calls. It cannot cancel calls already in progress. It currently works under ruby 1.8.7-p302 and 1.9.2-p0 on my computer running Mac OS X 10.6 (Snow Leopard). It is not guaranteed to work anywhere else and has very few tests.
EOS

  s.required_rubygems_version = "~> 1.3.6"
  # s.rubyforge_project         = "gvoice-ruby"
  
  s.add_dependency "curb", "~> 0.7.8"
  s.add_dependency "nokogiri", "~> 1.4.3.1"
  s.add_dependency "json", "~> 1.4.6"

  s.add_development_dependency "bundler", "~> 1.0.0.rc.6"
  s.add_development_dependency "mocha",  "~> 0.9.7"
  s.add_development_dependency "shoulda", "~> 2.11.3"
  s.add_development_dependency "rake", "~> 0.8.7"

  s.files        = `git ls-files`.split("\n")
  # s.executables  = ["bin/gv-notifier", "bin/gv-place-call", "bin/gv-send-sms"]#`git ls-files`.split("\n").select { |f| f =~ /^bin/ }
  s.require_paths = ['lib']
  
  s.post_install_message = "\n\nPlease run 'cd gvoice-ruby;bundle install;bundle exec rake' to run the tests.\n\n"
end
