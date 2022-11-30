module Ree
  module CLI
    class IndexProject
      class << self
        def run(project_path:)
          ENV['REE_SKIP_ENV_VARS_CHECK'] = 'true'

          path = Ree.locate_packages_schema(project_path)
          dir = Pathname.new(path).dirname.to_s

          Ree.init(dir)

          index_hash = {}
          index_hash[:classes] = {}

          facade = Ree.container.packages_facade

          facade.packages_store.packages.each do |package|
            next if package.gem?
            next if package.dir.nil?

            facade.load_entire_package(package.name)

            objects_class_names = package.objects.map(&:class_name)

            files = Dir[
              File.join(
                Ree::PathHelper.abs_package_module_dir(package), '**/*.rb'
              )
            ]

            files.each do |file_name|
              begin
                file_name_const_string = Ree::StringUtils.camelize(file_name.split('/')[-1].split('.rb')[0])
                const_string_with_module = "#{package.module}::#{file_name_const_string}"
                klass = Object.const_get(const_string_with_module)

                if objects_class_names.include?(const_string_with_module) &&
                  !klass.include?(ReeEnum::DSL)
                  next
                end

                methods = klass
                  .public_instance_methods(false)
                  .reject { _1.match?(/original/) } # remove aliases defined by contracts
                  .map {
                    {
                      name: _1,
                      location: klass.public_instance_method(_1).source_location&.last,
                    }
                  }

                rpath_from_root_file_path = Pathname.new(file_name).relative_path_from(Pathname.new(dir)).to_s
                hsh = {
                  path: rpath_from_root_file_path,
                  package: package.name,
                  methods: methods
                }

                index_hash[:classes][file_name_const_string] ||= []
                index_hash[:classes][file_name_const_string] << hsh
              rescue NameError
                next
              end
            end
          end

          if facade.get_package(:ree_errors, false)
            # add error constants
            package = facade.get_package(:ree_errors)

            package.objects.each do |obj|
              const_name = obj.class_name.split("::")[-1]
              file_name = File.join(
                Ree::PathHelper.abs_package_module_dir(package),
                obj.name.to_s + ".rb"
              )

              hsh = {
                path: file_name,
                package: package.name,
                methods: []
              }

              index_hash[:classes][const_name] ||= []
              index_hash[:classes][const_name] << hsh
            end
          end

          JSON.pretty_generate(index_hash)
        end
      end
    end
  end
end
