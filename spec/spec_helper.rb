require 'elastic_search_parser'
PERSON_MAPPING = YAML.load_file("#{File.dirname(__FILE__)}/mapping/person_mapping.yml")

def random_string(length = 10)
  (0..length).to_a.map{('a'..'z').to_a.sample}.join
end

def valid_person_mapping(opt = {})
  {
      id: random_string,
      first_names: [random_string.upcase, random_string],
      last_names:  [random_string, random_string.upcase],
      locations: [
          {
              state: random_string,
              city: random_string
          },
          {
              state: random_string,
              city: random_string.upcase
          }
      ]
  }.with_indifferent_access.merge(opt)
end