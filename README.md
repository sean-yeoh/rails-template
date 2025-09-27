## Requirements

This template currently requires:

- **Rails 8.0**
- **Ruby 3.4 or newer**
- PostgreSQL
- Sqlite3
- Node 20+ and Yarn 1.x
- Docker

## Usage

```$ bash
rails new <my_app> -d postgresql --skip-javascript \
  -m https://raw.githubusercontent.com/sean-yeoh/rails-template/main/template.rb
```

```bash
$ cd <my_app>
# the default database port is 5432, and if you already have it in use, change the port in my_app/.env
$ docker-compose up
$ rails db:create
$ rails db:migrate
$ docker-compose down
$ bin/dev
```

## What does it do?

The template will perform the following steps:

1. Generate your application files and directories
2. Add the following gems:

   - `sqlite3`: for solid cache/cable/queue
   - `vite_rails`: for javascript bundling instead of `esbuild`
   - `tailwindcss-rails`: for tailwind css

3. Add the following gems under `development` and `test` groups:

   - `standard`
   - `rubocop-rails`
   - `rubocop-minitest`
   - `rubocop-performance`
   - `rubocop-capybara`
   - `dotenv`

4. Add the `htmlbeautifier` gem under `development` group
5. Set the following development configs:

   - `config.active_job.queue_adapter = :solid_queue`
   - `config.solid_queue.connects_to = { database: { writing: :queue, reading: :queue } }`
   - `config.cache_store = :solid_cache_store`

6. Remove `rubocop-rails-omakase`
7. Add the following yarn dev dependencies:

   - `run-pty`
   - `neostandard`
   - `eslint`
   - `stylelint`
   - `stylelint-config-recommended`
   - `stylelint-config-tailwindcss`

8. Add the `vite-plugin-rails` yarn dependency
9. Replace `bin/dev` to use [run-pty](https://github.com/lydell/run-pty) instead of foreman for better process management
10. Remove `esbuild` yarn dependency since we're using `vite` for bundling
11. Run `rubocop` and `eslint` linters and commit everything to git
12. Update `config/cable.yml`, and `database.yml`
13. Create migration files for solid cache/cable/queue

## Credits

- https://github.com/mattbrictson/rails-template
- https://mattbrictson.com/blog/better-bin-dev-script
