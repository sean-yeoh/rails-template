require "bundler"
require "json"
RAILS_REQUIREMENT = "~> 8".freeze
NODE_REQUIREMENTS = ["~> 20"].freeze

def apply_template!
  assert_minimum_rails_version
  assert_minimum_node_version
  assert_postgresql
  add_template_repository_to_source_path

  template "env.template", ".env"
  template "env.template", "env.template"
  template "mise.toml.tt", "mise.toml"
  copy_file "eslint.config.mjs", "eslint.config.mjs"
  copy_file "stylelintrc.json", ".stylelintrc.json"
  copy_file "run-pty.json", "run-pty.json"
  copy_file "docker-compose.yml", "docker-compose.yml"
  copy_file "tsconfig.json", "tsconfig.json"
  copy_file "erb_lint.yml", ".erb_lint.yml"
  copy_file "lint.rake", "lib/tasks/lint.rake"

  gem "sqlite3"
  gem "vite_rails"
  gem "tailwindcss-rails"

  gem_group :development, :test do
    gem "dotenv"
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
    run "bundle exec vite install"
    run "rails tailwindcss:install"
    add_package_json_dependencies

    copy_file "vite.config.mts", "vite.config.mts", force: true
    copy_file "rubocop.yml", ".rubocop.yml", force: true
    copy_file "bin_dev", "bin/dev", force: true
    
    add_package_json_script("lintjs": "eslint 'app/javascript/**/*.{js,jsx}'")
    add_package_json_script("lintcss": "stylelint '**/*.css'")

    run_autocorrections
  
    run "rm package-lock.json"
    run "rm vite.config.ts"
    run "rm -rf node_modules"

    git checkout: "-b main"
    commit_files("First commit")

    say "Initial setup completed. Applying database configuration files.", :blue

    copy_file "cable.yml", "config/cable.yml", force: true
    template "database.yml.tt", "config/database.yml", force: true
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
    say "$ pnpm install", :blue
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
  # run "pnpm run \"/^lint/\""
end

def add_package_json_script(scripts)
  scripts.each do |name, script|
    run ["npm", "pkg", "set", "scripts.#{name.to_s.shellescape}=#{script.shellescape}"].join(" ")
  end
end

def add_package_json_dependencies
  run "npm install --save-dev run-pty eslint eslint-plugin-unicorn stylelint stylelint-config-recommended stylelint-config-tailwindcss @types/node"
  run "npm install vite-plugin-rails"
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