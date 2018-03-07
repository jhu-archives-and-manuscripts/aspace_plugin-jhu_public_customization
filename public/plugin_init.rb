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


  Record
  class Record

    # pre-override baseline of Record::parse_sub_container_display_string
    def parse_sub_container_display_string(sub_container, inst, opts = {})
      summary = opts.fetch(:summary, false)
      parts = []

      instance_type = I18n.t("enumerations.instance_instance_type.#{inst.fetch('instance_type')}", :default => inst.fetch('instance_type'))

      # add the top container type and indicator
      if sub_container.has_key?('top_container')
        top_container_solr = top_container_for_uri(sub_container['top_container']['ref'])
        if top_container_solr
          # We have a top container from Solr
          top_container_display_string = ""
          top_container_json = ASUtils.json_parse(top_container_solr.fetch('json'))
          if top_container_json['type']
            top_container_type = I18n.t("enumerations.container_type.#{top_container_json.fetch('type')}", :default => top_container_json.fetch('type'))
            top_container_display_string << "#{top_container_type}: "
          else
            top_container_display_string << "#{I18n.t('enumerations.container_type.container')}: "
          end
          top_container_display_string << top_container_json.fetch('indicator')
          parts << top_container_display_string
        elsif sub_container['top_container']['_resolved'] && sub_container['top_container']['_resolved']['display_string']
          # We have a resolved top container with a display string
          parts << sub_container['top_container']['_resolved']['display_string']
        end
      end


      # add the child type and indicator
      if sub_container['type_2'] && sub_container['indicator_2']
        type = I18n.t("enumerations.container_type.#{sub_container.fetch('type_2')}", :default => sub_container.fetch('type_2'))
        parts << "#{type}: #{sub_container.fetch('indicator_2')}"
      end

      # add the grandchild type and indicator
      if sub_container['type_3'] && sub_container['indicator_3']
        type = I18n.t("enumerations.container_type.#{sub_container.fetch('type_3')}", :default => sub_container.fetch('type_3'))
        parts << "#{type}: #{sub_container.fetch('indicator_3')}"
      end

      summary ? parts.join(", ") : "#{parts.join(", ")} (#{instance_type})"
    end

  end

end
