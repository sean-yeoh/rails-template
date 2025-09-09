namespace :lint do
  desc "Lint rb and erb files"

  task rubocop: :environment do
    puts "Running rubocop"
    system("bundle exec rubocop")
  end

  task erb_lint: :environment do
    puts "Running erb_lint"
    system("bundle exec erb_lint --lint-all")
  end
end
