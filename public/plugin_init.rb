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
      # this is just a parameterized version of public/app/models/record.rb:parse_repository_info()
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

    # include barcodes in top container summary information by overriding Record::parse_sub_container_display_string
    def parse_sub_container_display_string(sub_container, inst, opts = {})
      summary = opts.fetch(:summary, false)
      parts = []

      instance_type = I18n.t("enumerations.instance_instance_type.#{inst.fetch('instance_type')}", :default => inst.fetch('instance_type'))

      # add the top container type, indicator, and barcode (if available)
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
          if top_container_json['barcode']
            top_container_display_string << " [#{top_container_json.fetch('barcode')}]"
          end
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


  ResourcesController
  class ResourcesController

    # override show, infinite, and inventory methods and add resource_breadcrumb method to modularize breadcrumb config
    def show
      uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"
      begin
        @criteria = {}
        @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id', 'digital_object_uris:id']

        tree_root = archivesspace.get_raw_record(uri + '/tree/root') rescue nil
        @has_children = tree_root && tree_root['child_count'] > 0
        @has_containers = has_containers?(uri)

        @result =  archivesspace.get_record(uri, @criteria)
        @repo_info = @result.repository_information
        @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
        # @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => "xxx #{@result.identifier} #{process_mixed_content(@result.display_string)}"}]
        @context = resource_breadcrumb
        #      @rep_image = get_rep_image(@result['json']['instances'])
        fill_request_info
      rescue RecordNotFound
        @type = I18n.t('resource._singular')
        @page_title = I18n.t('errors.error_404', :type => @type)
        @uri = uri
        @back_url = request.referer || ''
        render  'shared/not_found', :status => 404
      end
    end

    def infinite
      @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"
      begin
        @criteria = {}
        @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id']
        @result =  archivesspace.get_record(@root_uri, @criteria)
        @has_containers = has_containers?(@root_uri)

        @repo_info = @result.repository_information
        @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
        # @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => "yyy [#{@result.identifier}] #{process_mixed_content(@result.display_string)}"}]
        @context = resource_breadcrumb
        fill_request_info
        @ordered_records = archivesspace.get_record(@root_uri + '/ordered_records').json.fetch('uris')
      rescue RecordNotFound
        @type = I18n.t('resource._singular')
        @page_title = I18n.t('errors.error_404', :type => @type)
        @uri = @root_uri
        @back_url = request.referer || ''
        render  'shared/not_found', :status => 404
      end
    end

    def inventory
      uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"

      tree_root = archivesspace.get_raw_record(uri + '/tree/root') rescue nil
      @has_children = tree_root && tree_root['child_count'] > 0

      begin
        # stuff for the collection bits
        @criteria = {}
        @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id']
        @result =  archivesspace.get_record(uri, @criteria)
        @repo_info = @result.repository_information
        @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
        # @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => "zzz [#{@result.identifier}] #{process_mixed_content(@result.display_string)}"}]
        @context = resource_breadcrumb
        fill_request_info

        # top container stuff ... sets @records
        fetch_containers(uri, "#{uri}/inventory", params)

        if !@results.blank?
          params[:q] = '*'
          @pager =  Pager.new(@base_search, @results['this_page'], @results['last_page'])
        else
          @pager = nil
        end

      rescue RecordNotFound
        @type = I18n.t('resource._singular')
        @page_title = I18n.t('errors.error_404', :type => @type)
        @uri = uri
        @back_url = request.referer || ''
        render  'shared/not_found', :status => 404
      end
    end

    # add identifier to top-level resource/collection context/breadcrumb
    def resource_breadcrumb
      [
          {:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name'], :level => "Repository", :type => "repository"},
          {:uri => nil, :crumb => process_mixed_content(@result.display_string),
           :identifier => @result.identifier, :level => "collection", :type => "resource"}
      ]

    end

  end


end
