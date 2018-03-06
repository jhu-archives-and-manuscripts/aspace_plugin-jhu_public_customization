my_app_dir = File.dirname(__FILE__)

ArchivesSpacePublic::Application.config.after_initialize do

  # Force the module to load
  ApplicationHelper
  module ApplicationHelper

    def repository_list
      repos = archivesspace.list_repositories
      repos.update(repos){ |uri, _| info = parse_repository_info(archivesspace.get_record(uri).json) }
      repos
    end

    def parse_repository_info(repository)
      # this is just a paramerterized version of public/app/models/record.rb:parse_repository_info()
      info = {}
      info['top'] = {}
      unless repository.nil?
        %w(name uri url parent_institution_name image_url repo_code).each do | item |
          info['top'][item] = repository[item] unless repository[item].blank?
        end
        unless repository['agent_representation'].blank? || repository['agent_representation']['_resolved'].blank? || repository['agent_representation']['_resolved']['jsonmodel_type'] != 'agent_corporate_entity'
          in_h = repository['agent_representation']['_resolved']['agent_contacts'][0]
          %w{city region post_code country email }.each do |k|
            info[k] = in_h[k] if in_h[k].present?
          end
          if in_h['address_1'].present?
            info['address'] = []
            [1,2,3].each do |i|
              info['address'].push(in_h["address_#{i}"]) if in_h["address_#{i}"].present?
            end
          end
          info['telephones'] = in_h['telephones'] if !in_h['telephones'].blank?
        end
      end
      info
    end

    private

    def archivesspace
      ArchivesSpaceClient.instance
    end

  end

end
