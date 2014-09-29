require 'utilrb/module/dsl_attribute'
require 'utilrb/module/include'
require 'utilrb/logger'
require 'fileutils'
require 'erb'
require 'typelib'

require 'fileutils'
require 'set'
require 'find'

class Module
    def enumerate_inherited_set(each_name, attribute_name = each_name) # :nodoc:
	class_eval <<-EOD, __FILE__, __LINE__
	def find_#{attribute_name}(name) 
            each_#{each_name} do |n|
                return n if n.name == name
            end
        end
	def all_#{attribute_name}; each_#{each_name}.to_a end
	def self_#{attribute_name}; @#{attribute_name} end
	def each_#{each_name}(&block)
	    if block_given?
		if superclass
		    superclass.each_#{each_name}(&block)
		end
		@#{attribute_name}.each(&block)
	    else
		enum_for(:each_#{each_name})
	    end
	end
	EOD
    end

    def enumerate_inherited_map(each_name, attribute_name = each_name) # :nodoc:
	class_eval <<-EOD, __FILE__, __LINE__
        attr_reader :#{attribute_name}
	def all_#{attribute_name}; each_#{each_name}.to_a end
	def self_#{attribute_name}; @#{attribute_name}.values end
	def has_#{attribute_name}?(name); !!find_#{each_name}(name) end

	def find_#{each_name}(name)
            name = name.to_str
	    if v = @#{attribute_name}[name]
		v
	    elsif superclass
		superclass.find_#{each_name}(name)
	    end
	end
	def each_#{each_name}(&block)
	    if block_given?
		if superclass
		    superclass.each_#{each_name}(&block)
		end
		@#{attribute_name}.each_value(&block)
	    else
		enum_for(:each_#{each_name})
	    end
	end
	EOD
    end
end


module Orocos
    OROGEN_LIB_DIR = File.expand_path(File.dirname(__FILE__))

    extend Logger::Root("Orocos", Logger::WARN)

    module Generation
        class InternalError < RuntimeError; end

        class ConfigError < Exception; end
	AUTOMATIC_AREA_NAME = '.orogen'

	extend Logger::Hierarchy
 
	@templates = Hash.new
	class << self
	    # The set of templates already loaded as a path => ERB object hash
	    attr_reader :templates
	end

        # Returns the directory where Orogen's lib part sits (i.e. where
        # autobuild.rb and autobuild/ are)
        def self.base_dir
	    File.expand_path('..', File.dirname(__FILE__))
        end

	# call-seq:
	#   template_path(path1, path2, ..., file_name)
	#
	# Returns the full path for the template path1/path2/.../file_name.
	# Templates names are the path relative to the template base directory,
	# which is the orocos/templates directory directly in Orocos.rb
	# sources.
	def self.template_path(*path)
	    reldir = File.join('templates', *path)
	    File.expand_path(reldir, File.dirname(__FILE__))
	end

	# call-seq:
	#   load_template path1, path2, ..., file_name => erb object
	#
	# Loads the template file located at
	# template_dir/path1/path2/.../file_name and return the ERB object
	# generated from it. template_dir is the templates/ directory located
	# in Orocos.rb sources.
	#
	# A template is only loaded once. See Generation.templates.
	def self.load_template(*path)
	    if template = templates[path]
		template
	    else
		template_file   = begin
				      template_path(*path)
				  rescue Errno::ENOENT
				      raise ArgumentError, "template #{File.join(*path)} does not exist"
				  end

		templates[path] = ERB.new(File.read(template_file), nil, "<>", path.join('_').gsub(/[\/\.-]/, '_'))
                templates[path].filename = template_file
                templates[path]
	    end
	end

	# call-seq:
	#   render_template path1, path2, file_name, binding
	#
	# Render the template found at path1/path2/file_name and render it
	# using the provided binding
	def self.render_template(*args)
	    binding = args.pop
	    template = load_template(*args)
	    logger.debug "rendering #{File.join(*args)}"
	    template.result(binding)
        rescue Exception => e
            raise e, "while rendering #{File.join(*args)}: #{e.message}", e.backtrace
	end

        class << self
            # The set of files generated so far, as a set of absolute paths
            attr_reader :generated_files
        end
        @generated_files = Set.new

	def self.save_generated(overwrite, *args) # :nodoc:
	    if args.size < 2
		raise ArgumentError, "expected at least 2 arguments, got #{args.size}"
	    end

	    data      = args.pop
	    file_path = File.expand_path(File.join(*args))
	    dir_name  = File.dirname(file_path)
	    FileUtils.mkdir_p(dir_name)

            generated_files << file_path
	    if File.exists?(file_path)
		if File.read(file_path) != data
		    if overwrite
			logger.info "  overwriting #{file_path}"
		    else
			logger.info "  will not overwrite #{file_path}"
			return file_path
		    end
		else
		    logger.debug "  #{file_path} has not changed"
		    return file_path
		end
	    else
		logger.info "  creating #{file_path}"
	    end

	    File.open(file_path, 'w') do |io|
		io.write data
	    end
            file_path
	end

        # Removes from the given path all files that have not been generated
        def self.cleanup_dir(*path)
            dir_path = File.expand_path(File.join(*path))

            Find.find(dir_path) do |file|
                if File.directory?(file) && File.directory?(File.join(file, "CMakeFiles"))
                    # This looks like a build directory. Ignore
                    Find.prune
                
                elsif File.file?(file) && !File.symlink?(file) && !generated_files.include?(file)
                    logger.info "   removing #{file}"
                    FileUtils.rm_f file
                end
            end
        end

        # call-seq:
        #   touch path1, path2, ..., file_name
        #
        # Creates an empty file path1/path2/.../file_name
        def self.touch(*args)
            path = File.expand_path(File.join(*args))
            FileUtils.touch path
            generated_files << path
        end

	# call-seq:
	#   save_automatic path1, path2, ..., file_name, data
	#
	# Save the provided data in the path1/path2/.../file_name file of the
	# automatically-generated part of the component (i.e. under .orogen)
	def self.save_automatic(*args)
	    save_generated true, AUTOMATIC_AREA_NAME, *args
	end
	
	# call-seq:
	#   save_public_automatic path1, path2, ..., file_name, data
	#
	# Save the provided data in the path1/path2/file_name file of the
	# user-written part of the component. It differs from save_user because
	# it will happily overwrite an existing file.
	def self.save_public_automatic(*args)
	    save_generated true, *args
	end
	
	# call-seq:
	#   save_user path1, path2, ..., file_name, data
	#
	# Save the provided data in the path1/path2/file_name file of the
	# user-written part of the component, if the said file does
	# not exist yet
	def self.save_user(*args)
	    result = save_generated false, *args

	    # Save the template in path1/path2/.../orogen/file_name
	    args = args.dup
	    args.unshift "templates"
	    save_generated true, *args
            result
	end

	# Returns the C++ code which changes the current namespace from +old+
	# to +new+. +indent_size+ is the count of indent spaces between
	# namespaces.
	def self.adapt_namespace(old, new, indent_size = 4)
	    old = old.split('/').delete_if { |v| v.empty? }
	    new = new.split('/').delete_if { |v| v.empty? }
	    indent = old.size * indent_size

	    result = ""

	    while !old.empty? && old.first == new.first
		old.shift
		new.shift
	    end
	    while !old.empty?
		indent -= indent_size
		result << " " * indent + "}\n"
		old.shift
	    end
	    while !new.empty?
		result << "#{" " * indent}namespace #{new.first} {\n"
		indent += indent_size
		new.shift
	    end

	    result
	end

	def self.really_clean
	    # List all files in templates and compare them w.r.t.  the ones in
	    # the user-side of the component. Remove those that are identical
	    base_dir     = Pathname.new('.')
	    template_dir = Pathname.new('templates')
	    template_dir.find do |path|
		next unless path.file?
		template_data = File.read(path.to_s)
		relative = path.relative_path_from(template_dir)

		if relative.file?
		    user_data = File.read(relative.to_s)
		    if user_data == template_data
			Generation.logger.info "removing #{relative} as it is the same than in template"
			FileUtils.rm_f relative.to_s
		    end
		end
	    end
	    
	    # Call #clean afterwards, since #clean removes the templates/ directory
	    clean
	end

        # Returns the unqualified version of +type_name+
        def self.unqualified_cxx_type(type_name)
            type_name.
                gsub(/(^|[^\w])const($|[^\w])/, '').
                gsub(/&/, '').
                strip
        end

	def self.clean
	    FileUtils.rm_rf Generation::AUTOMATIC_AREA_NAME
	    FileUtils.rm_rf "build"
	    FileUtils.rm_rf "templates"
	end

        class BuildDependency
            attr_reader :var_name
            attr_reader :pkg_name

            attr_reader :context

            def initialize(var_name, pkg_name)
                @var_name = var_name.gsub(/[^\w]/, '_')
                @pkg_name = pkg_name
                @context = []
            end

            def in_context(*args)
                context << args.to_set
                self
            end

            def remove_context(*args)
                args = args.to_set
                @context = context.dup
                context.delete_if do |ctx|
                    (args & ctx).size == args.size
                end
                self
            end

            def in_context?(*args)
                args = args.to_set
                context.any? do |ctx|
                    (args & ctx).size == args.size
                end
            end
        end

        def self.cmake_pkgconfig_require(depspec, context = 'core')
            depspec.inject([]) do |result, s|
                result << "orogen_pkg_check_modules(#{s.var_name} REQUIRED #{s.pkg_name})"
                if s.in_context?(context, 'include')
                    result << "include_directories(${#{s.var_name}_INCLUDE_DIRS})"
                    result << "add_definitions(${#{s.var_name}_CFLAGS_OTHER})"
                end
		if s.in_context?(context, 'link')
                    result << "link_directories(${#{s.var_name}_LIBRARY_DIRS})"
		end
                result
            end.join("\n") + "\n"
        end

        def self.cmake_pkgconfig_link(context, target, depspec)
            depspec.inject([]) do |result, s|
                if s.in_context?(context, 'link')
                    result << "target_link_libraries(#{target} ${#{s.var_name}_LIBRARIES})"
                end
                result
            end.join("\n") + "\n"
        end

        def self.cmake_pkgconfig_link_corba(target, depspec)
            cmake_pkgconfig_link('corba', target, depspec)
        end
        def self.cmake_pkgconfig_link_noncorba(target, depspec)
            cmake_pkgconfig_link('core', target, depspec)
        end

        def self.verify_valid_identifier(name)
            name = name.to_s if name.respond_to?(:to_sym)
            name = name.to_str
            if name !~ /^[a-zA-Z0-9_][a-zA-Z0-9_]*$/
                raise ArgumentError, "task name '#{name}' invalid: it can contain only alphanumeric characters and '_', and cannot start with a number"
            end
            name
        end
    end

    def self.each_orogen_plugin_path(&block)
        (ENV['OROGEN_PLUGIN_PATH'] || "").split(':').each(&block)
    end

    def self.each_orogen_plugin_dir
        each_orogen_plugin_path do |p|
            if File.directory?(p)
                yield(p)
            end
        end
    end

    def self.each_orogen_plugin_file(type)
        each_orogen_plugin_path do |path|
            if File.file?(path)
                yield(path)
            else
                Dir.glob(File.join(path, type, '*.rb')).each do |file|
                    yield(file)
                end
            end
        end
    end

    def self.load_orogen_plugin(*path)
        original_load_path = $LOAD_PATH.dup
        each_orogen_plugin_dir do |dir|
            $LOAD_PATH << dir
        end

        path = File.join(*path)
        if File.extname(path) != ".rb"
            path = "#{path}.rb"
        end

        each_orogen_plugin_dir do |dir|
            path = File.join(dir, path)
            if File.file?(path)
                logger.info "loading plugin #{path}"
                require path
                return
            end
        end
        raise ArgumentError, "cannot load plugin #{path}: not found in #{ENV['OROGEN_PLUGIN_PATH']}"

    ensure
        if original_load_path
            $LOAD_PATH.clear
            $LOAD_PATH.concat(original_load_path)
        end
    end

    def self.load_orogen_plugins(*type)
        original_load_path = $LOAD_PATH.dup
        type = File.join(*type)
        each_orogen_plugin_dir do |dir|
            $LOAD_PATH << dir
        end
        each_orogen_plugin_file(type) do |file|
            logger.info "loading plugin #{file}"
            begin
                require file
            rescue Exception => e
                logger.warn "could not load plugin #{file}: #{e.message}"
                e.backtrace.each do |line|
                    logger.warn "  #{line}"
                end
            end
        end
    ensure
        if original_load_path
            $LOAD_PATH.clear
            $LOAD_PATH.concat(original_load_path)
        end
    end

    # Load a separate typelib registry containing the types defined by the given
    # oroGen project
    def self.registry_of(typekit_name)
        registry = Typelib::Registry.new
        typekit_pkg =
            Utilrb::PkgConfig.new("#{typekit_name}-typekit-#{Orocos::Generation.orocos_target}")

        tlb = typekit_pkg.type_registry
        if tlb
            registry.import(tlb)
        end

        registry
    end

    def self.beautify_loading_errors(filename)
        yield
    rescue Exception => e
        # Two options:
        #  * the first line of the backtrace is the orogen file
        #    => change it into a ConfigError. If, in addition, this is a
        #       NoMethodError then change it into a statement error
        #  * the second line of the backtrace is in the orogen file
        #    => most likely a bad argument, transform it into a ConfigError
        #       too
        #  * all other cases are reported as internal errors
        file_pattern = /#{Regexp.quote(File.basename(filename))}/
        if e.backtrace.first =~ file_pattern
            if e.kind_of?(NoMethodError) || e.kind_of?(NameError)
                e.message =~ /undefined (?:local variable or )?method `([^']+)'/
                method_name = $1
                raise Generation::ConfigError, "unknown statement '#{method_name}'", e.backtrace
            else
                raise Generation::ConfigError, e.message, e.backtrace
            end
        elsif (e.backtrace[1] =~ file_pattern) || e.kind_of?(ArgumentError)
            raise Generation::ConfigError, e.message, e.backtrace
        end
        raise
    end
end

