require 'bundler/setup'
$:.unshift File.expand_path('../lib', __FILE__)

# rake spec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) { |t| t.verbose = false   }

# rake console
task :console do
  require 'pry'
  require 'gem_name'
  ARGV.clear
  Pry.start
end

namespace :db do
  desc 'Run the migrations to setup the application database.'
  task :migrate do
    require 'pg'

    sql = <<-SQL
CREATE TABLE IF NOT EXISTS posts (
  id SERIAL NOT NULL PRIMARY KEY,
  post_id UUID UNIQUE NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
  RETURNS TRIGGER LANGUAGE 'plpgsql'
  AS $BODY$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END
  $BODY$;

  DO $$
    BEGIN
      IF NOT EXISTS(SELECT *
        FROM information_schema.triggers
        WHERE event_object_table = 'posts'
        AND trigger_name = 'set_timestamp')
      THEN
        CREATE TRIGGER set_timestamp
          BEFORE UPDATE ON posts
          FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
      END IF;
    END;
  $$
SQL
    
    connect_hash = {
      host: ENV['DATABASE_HOST'] || 'localhost',
      dbname: ENV['DATABASE_NAME'] || 'hiveapp',
      user: ENV['DATABASE_USER'] || 'hiveappuser',
      password: ENV['DATABASE_PASSWORD'] || 'hiveappuser'
    }

    begin
      conn = PG.connect connect_hash
      conn.exec sql
    rescue PG::Error => e
      
    ensure
      conn.close if conn
    end
  end
end

namespace :deploy do

  task :push do
    puts 'Deploying to Heroku...'
    puts `git push heroku`
  end

  task :restart do
    puts 'Restarting app server...'
    puts `heroku restart`
  end

  task :tag do
    release_name = "release-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
    puts "Tagging release as '#{release_name}'"
    puts `git tag -a #{release_name} -M 'Tagged release'`
    puts `git push --tags heroku`
  end

  task :migrate do
    puts 'Running database migrations...'
    puts `heroku rake db:migrate`
  end

  task :off do
    puts 'Putting the app into maintenance mode...'
    puts `heroku maintenance:on`
  end

  task :on do
    puts 'Taking app out of maintenance mode...'
    puts `heroku maintenance:off`
  end
end
