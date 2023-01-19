module Ree
  module CLI
    class IndexProject
      class << self
        def run(project_path:)
          ENV['REE_SKIP_ENV_VARS_CHECK'] = 'true'

          path = Ree.locate_packages_schema(project_path)
          dir = Pathname.new(path).dirname.to_s

          Ree.init(dir)

          @index_hash = {}
          # completion/etc data
          @index_hash[:classes] = {}
          @index_hash[:objects] = {}

          # schema data
          @index_hash[:gem_paths] = {}
          @index_hash[:packages_schema] = {}
          @index_hash[:packages_schema][:packages] = []
          @index_hash[:packages_schema][:gem_packages] = []

          facade = Ree.container.packages_facade

          facade.packages_store.packages.each do |package|
            if package.gem?
              gem_package_hsh = {}
              gem_package_hsh[:name] = package.name
              gem_package_hsh[:gem] = package.gem_name
              gem_package_hsh[:schema_rpath] = package.schema_rpath
              gem_package_hsh[:entry_rpath] = package.entry_rpath
              gem_package_hsh[:objects] = package.objects.map {
                {
                  name: _1.name,
                  schema_rpath: _1.schema_rpath,
                  file_rpath: _1.rpath,
                  mount_as: _1.mount_as,
                  methods: map_fn_methods(_1),
                  links: _1.links.sort_by(&:object_name).map { |link|
                    {
                      Ree::ObjectSchema::Links::TARGET => link.object_name,
                      Ree::ObjectSchema::Links::PACKAGE_NAME => link.package_name,
                      Ree::ObjectSchema::Links::AS => link.as,
                      Ree::ObjectSchema::Links::IMPORTS => link.constants
                    }
                  }
                }
              }

              @index_hash[:packages_schema][:gem_packages] << gem_package_hsh

              next
            end

            next if package.dir.nil?
              
            facade.load_entire_package(package.name)

            package_hsh = Ree::CLI::IndexPackage.send(:map_package_entry, package)

            @index_hash[:packages_schema][:packages] << package_hsh

            objects_class_names = package.objects.map(&:class_name)

            files = Dir[
              File.join(
                Ree::PathHelper.abs_package_module_dir(package), '**/*.rb'
              )
            ]

            files.each do |file_name|
              begin
                const_string_from_file_name = Ree::StringUtils.camelize(file_name.split('/')[-1].split('.rb')[0])
                const_string_with_module = "#{package.module}::#{const_string_from_file_name}"
                klass = Object.const_get(const_string_with_module)

                if klass.include?(ReeEnum::DSL)
                  index_enum(klass, file_name, package.name, dir, const_string_from_file_name)

                  next
                end

                if klass.include?(ReeDao::DSL)
                  index_dao(klass, file_name, package.name, dir, const_string_from_file_name)
                  next
                end

                if klass.include?(ReeMapper::DSL)
                  # TODO
                  next
                end

                if !objects_class_names.include?(const_string_with_module)
                  index_class(klass, file_name, package.name, dir, const_string_from_file_name)

                  next
                end
              rescue NameError
                next
              end
            end
          end

          if facade.get_package(:ree_errors, false)
            index_exceptions(facade.get_package(:ree_errors))
          end
          

          JSON.pretty_generate(@index_hash)
        end

        private

        def index_class(klass, file_name, package_name, root_dir, hash_key)
          methods = klass
            .public_instance_methods(false)
            .reject { _1.match?(/original/) } # remove aliases defined by contracts
            .map {
              {
                name: _1,
                location: klass.public_instance_method(_1).source_location&.last,
              }
            }

          rpath_from_root_file_path = Pathname.new(file_name).relative_path_from(Pathname.new(root_dir)).to_s
          hsh = {
            path: rpath_from_root_file_path,
            package: package_name,
            methods: methods
          }

          @index_hash[:classes][hash_key] ||= []
          @index_hash[:classes][hash_key] << hsh
        end

        def index_enum(klass, file_name, package_name, root_dir, hash_key)
          index_class(klass, file_name, package_name, root_dir, hash_key)
        end

        def index_dao(klass, file_name, package_name, root_dir, hash_key)
          filters = klass
            .instance_variable_get(:@filters)
            .map {
              {
                name: _1.name,
                parameters: _1.proc.parameters.map { |param| { name: param.last, required: param.first } },
                location: _1.proc&.source_location&.last
              }
            }

          obj_name_key = Ree::StringUtils.underscore(hash_key)
          rpath_from_root_file_path = Pathname.new(file_name).relative_path_from(Pathname.new(root_dir)).to_s

          hsh = {
            path: rpath_from_root_file_path,
            package: package_name,
            methods: filters
          }

          @index_hash[:objects][obj_name_key] ||= []
          @index_hash[:objects][obj_name_key] << hsh
        end

        def index_exceptions(errors_package)
          errors_package.objects.each do |obj|
            const_name = obj.class_name.split("::")[-1]
            file_name = File.join(
              Ree::PathHelper.abs_package_module_dir(errors_package),
              obj.name.to_s + ".rb"
            )

            hsh = {
              path: file_name,
              package: errors_package.name,
              methods: []
            }

            @index_hash[:classes][const_name] ||= []
            @index_hash[:classes][const_name] << hsh
          end
        end
      end
    end
  end
end
