require 'elastic_search_parser'
PERSON_MAPPING = YAML.load_file("#{File.dirname(__FILE__)}/mapping/person_mapping.yml")