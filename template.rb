require "bundler"
require "json"
require "debug"
RAILS_REQUIREMENT = "~> 8".freeze
NODE_REQUIREMENTS = ["~> 20"].freeze

def apply_template!
  assert_minimum_rails_version
  assert_minimum_node_version
  assert_postgresql
  add_template_repository_to_source_path

  template "templates/env.template", ".env"
  template "templates/env.template", "env.template"
  template "templates/mise.toml.tt", "mise.toml"
  copy_file "templates/eslint.config.mjs", "eslint.config.mjs"
  copy_file "templates/stylelintrc.json", ".stylelintrc.json"
  copy_file "templates/run-pty.json", "run-pty.json"
  copy_file "templates/docker-compose.yml", "docker-compose.yml"
  copy_file "templates/tsconfig.json", "tsconfig.json"
  copy_file "templates/erb_lint.yml", ".erb_lint.yml"
  copy_file "templates/lib/tasks/lint.rake", "lib/tasks/lint.rake"

  gem "sqlite3"
  gem "vite_rails"
  gem "tailwindcss-rails"

  gem_group :development, :test do
    gem "dotenv"
    gem "playwright-ruby-client"
  end

  gem_group :development do
    gem "rubocop-shopify", require: false
    gem "rubocop-minitest", require: false
    gem "rubocop-performance", require: false
    gem 'erb_lint', require: false
    gem "htmlbeautifier", require: false
  end

  environment 'config.active_job.queue_adapter = :solid_queue', env: "development"
  environment 'config.solid_queue.connects_to = { database: { writing: :queue, reading: :queue } }', env: "development"
  environment 'config.cache_store = :solid_cache_store', env: "development"

  after_bundle do
    git checkout: "-b main"
    commit_files("First commit")

    run "mise install"

    run "pnpm install --save-dev vite"
    run "bundle exec vite install"
    copy_file "templates/vite.config.mts", "vite.config.mts", force: true
    commit_files("Run vite install")

    add_js_dependencies
    add_package_json_script("lintjs": "eslint 'app/frontend/**/*.{js,jsx,ts,tsx}'")
    add_package_json_script("lintcss": "stylelint 'app/**/*.css'")
    commit_files("Add js dependencies and lint scripts")

    run "rails tailwindcss:install"
    commit_files("Run tailwind install")

    copy_file "templates/vite.config.mts", "vite.config.mts", force: true
    copy_file "templates/rubocop.yml", ".rubocop.yml", force: true
    copy_file "templates/bin/dev", "bin/dev", force: true
    run_autocorrections
    commit_files("Replace rucobop, vite and bin/dev script")

    route "root 'home#index'"
    generate(:controller, "home index")
    create_file "app/views/home/index.html.erb", <<-ERB, force: true
    <h1>Welcome</h1>
    ERB
    copy_file "templates/test/system/home_test.rb", "test/system/home_test.rb", force: true
    copy_file "templates/test/application_system_test_case.rb", "test/application_system_test_case.rb", force: true

    commit_files("Setup files for playwright")


    say "Initial setup completed. Applying database configuration files.", :blue

    copy_file "templates/config/cable.yml", "config/cable.yml", force: true
    template "templates/config/database.yml.tt", "config/database.yml", force: true
    migration_version = "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    cable_content = File.read(File.join(destination_root, "db/cable_schema.rb"))
    cable_schema = cable_content[/ActiveRecord::Schema\[\d+\.\d+\]\.define\(.*?\) do\s*(.*)\s*end/m, 1]
    create_file "db/cable_migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_cable_schema.rb", "class CreateCableSchema < ActiveRecord::Migration[#{migration_version}]\n#{cable_schema}\nend"

    cache_content = File.read(File.join(destination_root, "db/cache_schema.rb"))
    cache_schema = cache_content[/ActiveRecord::Schema\[\d+\.\d+\]\.define\(.*?\) do\s*(.*)\s*end/m, 1]
    create_file "db/cache_migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_cache_schema.rb", "class CreateCacheSchema < ActiveRecord::Migration[#{migration_version}]\n#{cache_schema}\nend"

    queue_content = File.read(File.join(destination_root, "db/queue_schema.rb"))
    queue_schema = queue_content[/ActiveRecord::Schema\[\d+\.\d+\]\.define\(.*?\) do\s*(.*)\s*end/m, 1]
    create_file "db/queue_migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_queue_schema.rb", "class CreateQueueSchema < ActiveRecord::Migration[#{migration_version}]\n#{queue_schema}\nend"

    run_autocorrections
    commit_files("Apply database configuration files")
    
    

    say "Successfully applied rails template.", :green
    say "To complete the setup, please run the following commands to setup primary and solid cache/cable/queue databases.", :blue
    say "It will create a postgresql database in docker, and sqlite3 database for solid cache/cable/queue.", :blue
    say "$ cd #{app_name}", :blue
    say "$ docker-compose up -d", :blue
    say "$ rails db:create", :blue
    say "$ rails db:migrate", :blue
    say "$ docker-compose down", :blue
  end
end

require "fileutils"
require "shellwords"

# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/sean-yeoh/rails-template.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def assert_minimum_node_version
  requirements = NODE_REQUIREMENTS.map { Gem::Requirement.new(_1) }
  node_version = `node --version`.chomp rescue nil
  if node_version.nil?
    fail Rails::Generators::Error, "This template requires Node, but Node does not appear to be installed."
  end

  return if requirements.any? { _1.satisfied_by?(Gem::Version.new(node_version[/[\d.]+/])) }

  prompt = "This template requires Node #{NODE_REQUIREMENTS.join(" or ")}. "\
           "You are using #{node_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def assert_postgresql
  return if IO.read("Gemfile") =~ /^\s*gem ['"]pg['"]/
  fail Rails::Generators::Error, "This template requires PostgreSQL, but the pg gem isn't present in your Gemfile."
end

def commit_files(message)
  git add: "-A ."
  git commit: "-n -m '#{message}'"
end

def run_autocorrections
  run_with_clean_bundler_env "bin/rubocop -A --fail-level A > /dev/null || true"
  run "pnpm run \"/^lint/\" --fix"
end

def add_package_json_script(scripts)
  scripts.each do |name, script|
    run ["pnpm", "pkg", "set", "scripts.#{name.to_s.shellescape}=#{script.shellescape}"].join(" ")
  end
end

def add_js_dependencies
  run "pnpm install --save-dev run-pty eslint eslint-plugin-unicorn @eslint/js typescript typescript-eslint globals stylelint stylelint-config-recommended stylelint-config-tailwindcss @types/node playwright"
  run "pnpm install vite-plugin-rails"
end

def run_with_clean_bundler_env(cmd)
  success = if defined?(Bundler)
              if Bundler.respond_to?(:with_original_env)
                Bundler.with_original_env { run(cmd) }
              else
                Bundler.with_clean_env { run(cmd) }
              end
            else
              run(cmd)
            end
  unless success
    puts "Command failed, exiting: #{cmd}"
    exit(1)
  end
end

apply_template!