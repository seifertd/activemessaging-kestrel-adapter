begin
  require 'bones'
rescue LoadError
  abort '### Please install the "bones" gem ###'
end

task :default => 'test:run'
task 'gem:release' => 'test:run'

Bones {
  name     'activemessaging-kestrel-adapter'
  authors  'Douglas A. Seifert'
  email    'doug@dseifert.net'
  url      'http://github.org/seifertd/activemessaging-kestrel-adapter'
  ignore_file '.gitignore'
  readme_file 'README.md'
  version '0.0.1'

  depend_on 'memcache-client'

  rdoc.include << 'README.md'

}

