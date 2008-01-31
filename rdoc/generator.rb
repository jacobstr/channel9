require 'cgi'
require 'rdoc'
require 'rdoc/options'
require 'rdoc/markup'
require 'rdoc/template'

module RDoc::Generator

  ##
  # Name of sub-direcory that holds file descriptions

  FILE_DIR  = "files"

  ##
  # Name of sub-direcory that holds class descriptions

  CLASS_DIR = "classes"

  ##
  # Name of the RDoc CSS file

  CSS_NAME  = "rdoc-style.css"

end

