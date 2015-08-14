require 'elastic_search_parser'
PERSON_MAPPING = YAML.load_file("#{File.dirname(__FILE__)}/mapping/person_mapping.yml")

def random_string(length = 10)
  (0..length).to_a.map{('a'..'z').to_a.sample}.join
end

def valid_person_mapping(opt = {})
  {
      first_name: random_string,
      last_name:  random_string,
      locations: [
          {
              state: random_string,
              city: random_string
          }
      ]
  }.with_indifferent_access.merge(opt)
end